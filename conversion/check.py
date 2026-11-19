"""Representative conversion and failure checks, using synthetic notes only."""
import json
from pathlib import Path
import tempfile
import shutil
import wave
import zipfile

from libresvip.model.base import InstrumentalTrack, Note, Project, SingingTrack, SongTempo, TimeSignature
from convert import CONVERTERS, WRITE_ONLY, convert, converter, romanize


def main():
    project = Project(song_tempo_list=[SongTempo(position=0, bpm=120)],
        time_signature_list=[TimeSignature(bar_index=0, numerator=4, denominator=4)],
        track_list=[SingingTrack(title='Synthetic', note_list=[
            Note(start_pos=0, length=480, key_number=60, lyric='重'),
            Note(start_pos=480, length=480, key_number=62, lyric='庆'),
            Note(start_pos=960, length=480, key_number=64, lyric='好')])])
    romanized = project.model_copy(deep=True)
    romanize(romanized)
    assert [n.lyric for n in romanized.track_list[0].note_list] == ['chong', 'qing', 'hao']
    results = {}
    with tempfile.TemporaryDirectory(prefix='checks-', dir=Path(__file__).parent) as root:
        root = Path(root)
        source = root/'source.json'
        converter('json').dump(source, project, {})
        for fmt in CONVERTERS:
            target = root/f'converted.{fmt}'
            try:
                options = '{"encoding":"UTF-8"}' if fmt == 'ust' else '{}'
                convert(source, target, 'json', fmt, output_options=options)
                assert target.stat().st_size > 0
                if fmt not in WRITE_ONLY:
                    loaded = converter(fmt).load(target, json.loads(options))
                    notes = [n for t in loaded.track_list if isinstance(t,SingingTrack) for n in t.note_list]
                    assert [(n.key_number,n.start_pos,n.length) for n in notes] == [(60,0,480),(62,480,480),(64,960,480)], [(n.key_number,n.start_pos,n.length) for n in notes]
                results[fmt] = {'export': 'passed', 'roundtrip': 'export-only' if fmt in WRITE_ONLY else 'passed'}
            except Exception as error:
                results[fmt] = {'status': 'failed', 'error': str(error)}
        for name, options, expected_type in [('ai-import', '{"is_ai_singer":true}', 2),
                                             ('legacy-explicit', '{"is_ai_singer":false}', 0),
                                             ('unchanged-export', '{}', 0)]:
            destination = root / (name + '.vpr')
            convert(source, destination, 'json', 'vpr', output_options=options)
            with zipfile.ZipFile(destination) as archive:
                raw = json.loads(archive.read('Project/sequence.json'))
                assert raw['tracks'][0]['type'] == expected_type
        snapshots = root/'snapshots'
        snapshots.mkdir()
        output = root/'output'
        output.mkdir()
        wave_file = snapshots/'test.wav'
        with wave.open(str(wave_file), 'wb') as audio:
            audio.setnchannels(1)
            audio.setsampwidth(2)
            audio.setframerate(44100)
            audio.writeframes(b'\x00\x00' * 4410)
        with_audio = project.model_copy(deep=True)
        with_audio.track_list.append(InstrumentalTrack(title='test',audio_file_path=str(wave_file.resolve())))
        snapshot = snapshots/'snapshot.vprx'
        converter('vpr').dump(snapshot,with_audio,{})
        wave_file.unlink()
        assets = convert(snapshot,output/'with-audio.json','vprx','json')
        assert assets and Path(assets).is_dir()
        before = set(output.iterdir())
        try:
            convert(snapshot,output/'failure.ust','vprx','ust')
            raise AssertionError('Expected unsupported Shift-JIS characters')
        except UnicodeEncodeError:
            assert set(output.iterdir()) == before
        shutil.rmtree(snapshots)
        loaded_audio = converter('json').load(output/'with-audio.json',{})
        paths = [Path(t.audio_file_path) for t in loaded_audio.track_list if isinstance(t,InstrumentalTrack)]
        assert len(paths) == 1 and paths[0].is_file()
        with wave.open(str(paths[0]),'rb') as audio:
            assert audio.getnframes() == 4410
        compressed = root/'score.mxl'
        convert(source, compressed, 'json', 'mxl')
        loaded = converter('mxl').load(compressed,{})
        assert len(loaded.track_list[0].note_list) == 3
        existing=root/'existing.json'
        existing.write_text('preserve')
        try:
            convert(source,existing,'json','json')
            raise AssertionError('Expected existing destination rejection')
        except FileExistsError:
            assert existing.read_text()=='preserve'
        try:
            convert(source,root/'bad.json','json','json',output_options='{"unknown":true}')
            raise AssertionError('Expected invalid option rejection')
        except ValueError:
            assert not (root/'bad.json').exists()
        try:
            convert(source,root/'bad.vprx','json','vprx')
            raise AssertionError('Expected unsupported VPRX rejection')
        except ValueError:
            assert not (root/'bad.vprx').exists()
    Path(__file__).with_name('validation.json').write_text(json.dumps(results,ensure_ascii=False,indent=2)+'\n')
    print(json.dumps(results,ensure_ascii=False,indent=2))
    assert all(result.get('export') == 'passed' for result in results.values()), 'A format check failed'


if __name__=='__main__':
    main()
