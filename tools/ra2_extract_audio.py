#!/usr/bin/env python3
from __future__ import annotations
import argparse, json, shutil, subprocess, tempfile, zipfile
from pathlib import Path


def main() -> int:
    ap=argparse.ArgumentParser(description='Extract Westwood AUD audio and transcode to Godot-compatible OGG')
    ap.add_argument('archive', type=Path)
    ap.add_argument('output', type=Path)
    args=ap.parse_args()
    ffmpeg=shutil.which('ffmpeg')
    if not ffmpeg:
        raise SystemExit('ffmpeg is required to decode Westwood AUD files')
    args.output.mkdir(parents=True, exist_ok=True)
    manifest=[]
    with zipfile.ZipFile(args.archive) as z, tempfile.TemporaryDirectory() as td:
        temp=Path(td)
        for info in z.infolist():
            if not info.filename.lower().endswith('.aud'):
                continue
            safe=Path(info.filename)
            stem='_'.join(safe.with_suffix('').parts).lower()
            aud=temp/(stem+'.aud')
            ogg=args.output/(stem+'.ogg')
            aud.write_bytes(z.read(info))
            proc=subprocess.run([ffmpeg,'-hide_banner','-loglevel','error','-y','-i',str(aud),'-c:a','libvorbis','-q:a','4',str(ogg)],capture_output=True,text=True)
            if proc.returncode != 0 and not ogg.exists():
                print(f'warning: failed {info.filename}: {proc.stderr.strip()}')
                continue
            manifest.append({'source':info.filename,'resource':'res://'+ogg.as_posix().split('/iron_meridian_rts_v0.9.3/',1)[-1]})
    (args.output/'manifest.json').write_text(json.dumps({'version':1,'assets':manifest},ensure_ascii=False,indent=2),encoding='utf-8')
    print(json.dumps({'ok':True,'converted':len(manifest),'output':str(args.output)},ensure_ascii=False))
    return 0
if __name__=='__main__': raise SystemExit(main())
