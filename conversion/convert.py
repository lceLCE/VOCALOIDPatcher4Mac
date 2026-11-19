#!/usr/bin/env python3
"""Local format bridge for the macOS VOCALOIDPatcher. Requires LibreSVIP 2.9.2."""
from __future__ import annotations

import argparse
import importlib
import shutil
import json
import os
from pathlib import Path
import sys
import tempfile
import zipfile

# Import packaged converters directly, without loading user-installed plugin code.
CONVERTERS = {
    'ustx': ('ustx.ustx_converter', 'OpenUtauConverter'),
    'ust': ('ust.ust_converter', 'USTConverter'),
    'svp': ('svp.synthv_studio_converter', 'SynthVStudioConverter'),
    's5p': ('s5p.synthv_editor_converter', 'SynthVEditorConverter'),
    'vsq': ('vsq.vsq_converter', 'VocaloidSequenceConverter'),
    'vsqx': ('vsqx.vsqx_converter', 'VsqxConverter'),
    'vpr': ('vpr.vpr_converter', 'VocaloidConverter'),
    'ccs': ('ccs.cevio_converter', 'CeVIOConverter'),
    'tssln': ('tssln.voisona_converter', 'VoiSonaConverter'),
    'acep': ('acep.ace_studio_converter', 'ACEStudioConverter'),
    'vvproj': ('vvproj.voicevox_converter', 'VOICEVOXConverter'),
    'ppsf': ('ppsf.piapro_studio_converter', 'PiaproStudioConverter'),
    'dv': ('dv.deepvocal_converter', 'DeepVocalConverter'),
    'tlpx': ('tlpx.tlpx_converter', 'TuneLabXConverter'),
    'tlp': ('tlp.tunelab_converter', 'TuneLabConverter'),
    'svip': ('svip.binsvip_converter', 'SvipConverter'),
    'ds': ('ds.diffsinger_converter', 'DiffSingerConverter'),
    'aisp': ('aisp.aisingers_converter', 'AiSingersConverter'),
    'y77': ('y77.y77_converter', 'Y77Converter'),
    'vog': ('vog.vogen_converter', 'VogenConverter'),
    'musicxml': ('musicxml.musicxml_converter', 'MusicXMLConverter'),
    'json': ('json.jsonsvip_converter', 'JsonSvipConverter'),
    'ufdata': ('ufdata.ufdata_converter', 'UFDataConverter'),
    'lrc': ('lrc.lrc_converter', 'LrcConverter'),
    'srt': ('srt.srt_converter', 'SrtConverter'),
    'ass': ('ass.ass_converter', 'AssConverter'),
    'mid': ('mid.midi_converter', 'MidiConverter'),
}
ALIASES = {'xml': 'musicxml', 'mxl': 'musicxml', 'midi': 'mid'}
WRITE_ONLY = {'lrc', 'srt', 'ass'}


def converter(format_name: str):
    """Return a known bundled converter, rejecting arbitrary module names."""
    format_name = ALIASES.get(format_name.lower(), format_name.lower())
    if format_name == 'vprx':
        raise ValueError('VPRX is not supported by this bridge. Export an editor snapshot as OpenSVIP JSON first.')
    if format_name not in CONVERTERS:
        raise ValueError(f'Unsupported format: {format_name}')
    module, name = CONVERTERS[format_name]
    return getattr(importlib.import_module(f'libresvip.plugins.{module}'), name)


def validated_options(plugin, direction: str, value: str) -> dict:
    options = json.loads(value)
    if not isinstance(options, dict):
        raise ValueError('Options must be a JSON object')
    option_class = getattr(plugin, f'{direction}_option_cls')
    unknown = options.keys() - option_class.model_fields.keys()
    if unknown:
        raise ValueError(f'Unknown {direction} options: {", ".join(sorted(unknown))}')
    return option_class.model_validate(options).model_dump()


def romanize(project) -> None:
    """Use phrase context across notes, preserving supplied pronunciation."""
    from libresvip.core.lyric_phoneme.chinese import CHINESE_RE, get_pinyin_series
    from libresvip.model.base import SingingTrack
    for track in project.track_list:
        if isinstance(track, SingingTrack):
            notes = track.note_list
            readings = get_pinyin_series([note.lyric for note in notes])
            for note, reading in zip(notes, readings, strict=True):
                if CHINESE_RE.search(note.lyric):
                    note.lyric = note.pronunciation or reading or note.lyric


def convert(source: Path, target: Path, source_format: str, target_format: str,
            input_options: str = '{}', output_options: str = '{}',
            pinyin: bool = False, overwrite: bool = False) -> str | None:
    source_format = source_format.lower()
    target_format = target_format.lower()
    if source_format in WRITE_ONLY:
        raise ValueError(f'{source_format} supports export only')
    if source.resolve() == target.resolve():
        raise ValueError('Source and destination must be different files')
    if target.exists() and not overwrite:
        raise FileExistsError('Destination already exists. Choose another name or use --overwrite.')
    reader = converter('vpr' if source_format == 'vprx' else source_format)
    writer = converter(target_format)
    load_options = validated_options(reader, 'input', input_options)
    dump_options = validated_options(writer, 'output', output_options)
    # Keep extraction under our control. The upstream option writes beside the
    # input and can leave exported projects pointing at a temporary snapshot.
    if 'extract_audio' in load_options:
        load_options['extract_audio'] = False
    project = reader.load(source, load_options)
    assets = None
    if source_format in {'vpr', 'vprx'}:
        from libresvip.model.base import InstrumentalTrack
        try:
            with zipfile.ZipFile(source) as archive:
                data = json.loads(archive.read('Project/sequence.json'))
                embedded = {}
                for track in data.get('tracks', []):
                    for part in track.get('parts', []):
                        audio = part.get('wav')
                        if audio:
                            name = audio.get('name', '')
                            if Path(name).name != name or '\\' in name or name in {'.', '..'}:
                                raise ValueError('Embedded audio name must be a plain filename')
                            original = audio.get('originalName') or name
                            embedded[str(source.parent / original)] = 'Project/Audio/' + name
                for track in project.track_list:
                    if not isinstance(track, InstrumentalTrack) or Path(track.audio_file_path).is_file():
                        continue
                    member = embedded.get(track.audio_file_path)
                    if member is None or member not in archive.namelist():
                        continue
                    if assets is None:
                        assets = Path(tempfile.mkdtemp(prefix=target.name + '.audio-', dir=target.parent)).resolve()
                    destination = assets / Path(member).name
                    with archive.open(member) as input_file, destination.open('wb') as output_file:
                        shutil.copyfileobj(input_file, output_file)
                    track.audio_file_path = str(destination)
        except BaseException:
            if assets is not None:
                shutil.rmtree(assets)
            raise
    published = False
    try:
        if pinyin:
            romanize(project)
        # Converters finish in a private directory before publishing any output.
        with tempfile.TemporaryDirectory(prefix='.vocaloid-convert-', dir=target.parent) as staging:
            staged = Path(staging) / target.name
            if target_format == 'mxl':
                score = Path(staging) / 'score.musicxml'
                writer.dump(score, project, dump_options)
                with zipfile.ZipFile(staged, 'w', zipfile.ZIP_DEFLATED) as archive:
                    archive.writestr('mimetype', 'application/vnd.recordare.musicxml',
                                     compress_type=zipfile.ZIP_STORED)
                    archive.write(score, 'score.musicxml')
                    archive.writestr('META-INF/container.xml',
                        '<?xml version="1.0"?><container version="1.0"><rootfiles><rootfile full-path="score.musicxml" media-type="application/vnd.recordare.musicxml+xml"/></rootfiles></container>')
            else:
                writer.dump(staged, project, dump_options)
            if not staged.is_file():
                raise RuntimeError('Converter did not produce the requested output file')
            if overwrite:
                os.replace(staged, target)
            else:
                # An exclusive hard link prevents a racing export from overwriting a file.
                os.link(staged, target)
        published = True
        return str(assets) if assets is not None else None
    finally:
        if assets is not None and not published:
            shutil.rmtree(assets)


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--formats', action='store_true')
    parser.add_argument('--options', metavar='FORMAT')
    parser.add_argument('source', type=Path, nargs='?')
    parser.add_argument('target', type=Path, nargs='?')
    parser.add_argument('--from', dest='source_format')
    parser.add_argument('--to', dest='target_format')
    parser.add_argument('--input-options', default='{}')
    parser.add_argument('--output-options', default='{}')
    parser.add_argument('--pinyin', action='store_true')
    parser.add_argument('--overwrite', action='store_true')
    args = parser.parse_args()
    if args.formats:
        print(json.dumps([{ 'format': name, 'import': name not in WRITE_ONLY, 'export': True }
                          for name in CONVERTERS] + [{'format': 'vprx', 'import': True, 'export': False}], ensure_ascii=False))
        return
    if args.options:
        args.options = args.options.lower()
        plugin = converter('vpr' if args.options == 'vprx' else args.options)
        result = {}
        for direction in ('input', 'output'):
            option_class = getattr(plugin, f'{direction}_option_cls', None)
            if option_class and not (args.options == 'vprx' and direction == 'output'):
                result[direction] = option_class.model_json_schema()
        print(json.dumps(result, ensure_ascii=False))
        return
    if args.source is None or args.target is None:
        parser.error('source and target are required')
    source_format = args.source_format or args.source.suffix[1:].lower()
    target_format = args.target_format or args.target.suffix[1:].lower()
    from libresvip.core.warning_types import CatchWarnings
    with CatchWarnings() as warnings:
        assets = convert(args.source, args.target, source_format, target_format, args.input_options,
                args.output_options, args.pinyin, args.overwrite)
    print(json.dumps({'output': str(args.target.resolve()), 'status': 'ok',
                      'warnings': warnings.output.splitlines(), 'audio_directory': assets}))


if __name__ == '__main__':
    try:
        main()
    except Exception as error:
        print(json.dumps({'status': 'error', 'message': str(error)}, ensure_ascii=False), file=sys.stderr)
        raise SystemExit(1)
