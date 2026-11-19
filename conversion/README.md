# macOS format bridge

Requires Python 3.12 and the pinned dependencies in requirements.txt. Run setup.command to create a local environment. No global Python package installation is required.

```
.venv/bin/python convert.py source.vprx output.svp
.venv/bin/python convert.py source.ustx output.vpr --pinyin
.venv/bin/python convert.py source.json output.ust --output-options '{"encoding":"UTF-8"}'
.venv/bin/python convert.py --formats
.venv/bin/python convert.py --options vsqx
.venv/bin/python check.py
```

The editor should pass an argument array to a subprocess. Never interpolate project filenames or option JSON into a shell command. The helper prints one JSON status object on stdout, including conversion warnings. Errors return exit status 1 and a JSON error on stderr. Existing output is protected unless --overwrite is explicitly passed. The source and destination must differ. A finished output is published atomically on the same filesystem.

The converter covers all 26 upstream format entries plus MIDI. `xml` and `mxl` input aliases use the MusicXML reader. MXL export writes compressed MusicXML with a META-INF/container.xml manifest. Subtitles support export only. Select a singing track through the format's `track_index` option when appropriate. UST's upstream default encoding is Shift-JIS. Use UTF-8 explicitly for Chinese lyrics. Output limits and converter options remain those of LibreSVIP 2.9.2.

VPRX input was verified against Yamaha's installed VOCALOID7 DemoSong.vprx, whose ZIP contains Project/sequence.json with major version 7. The reader produced its 310 singing notes, tempo and time signature, plus one accompaniment reference. Extraction of its embedded WAV was also verified on a private copy of the sample. VPRX output is handled by the editor. Conversion uses LibreSVIP's VPR model, so V7-specific voice controls and synthesis settings have not been verified for preservation.

Missing embedded VPR/VPRX accompaniment is extracted into a unique audio directory beside the destination. Its files remain available after the editor's snapshot directory is deleted. The helper never extracts beside the original input. Existing external audio references are preserved when their files exist. Generated projects that reference this audio must keep the returned `audio_directory` available. The JSON result reports its path. Failed conversions remove the newly created directory. An externally terminated conversion may leave an unused audio directory.


Validation uses a synthetic three-note project. All 27 formats exported successfully. All 24 readable formats round-tripped pitch, start and duration. The UST check explicitly uses UTF-8. Contextual Chinese pinyin, invalid options, existing-output protection and unsupported VPRX output also passed. A synthetic WAV accompaniment survives deletion of the snapshot directory, and a failed export cleans its new audio directory. These checks establish basic conversion behavior. Audio, complex pitch curves, every metadata field and target-editor rendering remain outside this check.

LibreSVIP 2.9.2 is MIT licensed. Its own package includes upstream license metadata. Source repository https://github.com/SoulMelody/LibreSVIP . This bridge was created for the GPL-3.0 VOCALOIDPatcher macOS port.

MXL container reference https://www.w3.org/2021/06/musicxml40/tutorial/compressed-mxl-files/ .
