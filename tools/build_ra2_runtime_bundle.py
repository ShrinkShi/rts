#!/usr/bin/env python3
"""Build disposable Godot caches from a canonical RA2/YR map and theater files."""
from __future__ import annotations
import argparse,base64,hashlib,json,math,struct,zlib
from dataclasses import dataclass
from pathlib import Path
from ra2_ini import RA2MapError
from ra2_map_enrichment import enrich_imported_map
from ra2_map_importer import import_map
from ra2_palette import Palette,load_palette
from ra2_shp_ts import ShpTsError,ShpTsFile,indexed_to_rgba
from ra2_theater import ArchiveStack,CaseInsensitiveZip,TheaterCatalog
from ra2_tmp import render_rgba
CELL_STRUCT=struct.Struct('<HHBBB');RESOURCE_STRUCT=struct.Struct('<HHHBB');CELL_WIDTH=60;CELL_HEIGHT=30;HEIGHT_STEP=15;PNG_SIGNATURE=b'\x89PNG\r\n\x1a\n';ORE_ID_FIRST=105;ORE_ID_LAST=124;GEM_ID_FIRST=28;GEM_ID_LAST=39
@dataclass(frozen=True)
class RenderedTile:width:int;height:int;origin_x:int;origin_y:int;rgba:bytes
@dataclass(frozen=True)
class AtlasAsset:asset_id:str;width:int;height:int;rgba:bytes;palette_name:str;source_name:str;frame:int
def _png_chunk(kind,payload):return struct.pack('>I',len(payload))+kind+payload+struct.pack('>I',zlib.crc32(kind+payload)&0xffffffff)
def encode_png_rgba(width,height,rgba,*,level=9):
    if width<=0 or height<=0:raise RA2MapError(f'PNG dimensions must be positive, got {width}x{height}')
    if len(rgba)!=width*height*4:raise RA2MapError(f'RGBA length mismatch: expected {width*height*4}, got {len(rgba)}')
    scan=bytearray();stride=width*4
    for row in range(height):scan.append(0);scan.extend(rgba[row*stride:(row+1)*stride])
    header=struct.pack('>IIBBBBB',width,height,8,6,0,0,0)
    return PNG_SIGNATURE+_png_chunk(b'IHDR',header)+_png_chunk(b'IDAT',zlib.compress(bytes(scan),level))+_png_chunk(b'IEND',b'')
def alpha_blit(destination,dw,dh,source,sw,sh,left,top):
    if len(source)!=sw*sh*4:raise RA2MapError('Source RGBA length does not match its dimensions')
    for sy in range(sh):
        dy=top+sy
        if dy<0 or dy>=dh:continue
        for sx in range(sw):
            dx=left+sx
            if dx<0 or dx>=dw:continue
            so=(sy*sw+sx)*4;a=source[so+3]
            if a==0:continue
            do=(dy*dw+dx)*4
            if a==255:destination[do:do+4]=source[so:so+4];continue
            inv=255-a
            for channel in range(3):destination[do+channel]=(source[so+channel]*a+destination[do+channel]*inv)//255
            destination[do+3]=min(255,a+destination[do+3]*inv//255)
def write_base64_chunks(payload,output_dir,stem,*,chunk_characters=900000):
    if chunk_characters<4:raise RA2MapError('Base64 chunk size must be at least four characters')
    chunk_characters-=chunk_characters%4;encoded=base64.b64encode(payload).decode('ascii');count=max(1,math.ceil(len(encoded)/chunk_characters));output_dir.mkdir(parents=True,exist_ok=True)
    for stale in output_dir.glob(f'{stem}_*.b64'):stale.unlink()
    for index in range(count):(output_dir/f'{stem}_{index:02d}.b64').write_text(encoded[index*chunk_characters:(index+1)*chunk_characters]+'\n',encoding='ascii')
    return count
def _project_cell(rx,ry,source_width,level,baseline):return ((rx-ry+source_width-1)*(CELL_WIDTH//2)+CELL_WIDTH//2,(rx+ry-source_width-1)*(CELL_HEIGHT//2)+baseline-level*HEIGHT_STEP+CELL_HEIGHT//2)
def _terrain_render_cache(imported,palette,catalog,archives):
    cache={};tmp_cache={}
    for raw in imported.get('tiles',[]):
        tile=dict(raw);ti=int(tile['tile_index']);sub=int(tile['sub_tile']);key=(ti,sub)
        if key in cache:continue
        tmp=tmp_cache.get(ti)
        if tmp is None:tmp=catalog.load_tmp(ti,archives);tmp_cache[ti]=tmp
        cache[key]=RenderedTile(*render_rgba(tmp,sub,palette,include_extra=True))
    return cache
def render_terrain(imported,palette,catalog,archives):
    sw=int(imported['map']['width']);baseline=sw*(CELL_HEIGHT//2)+180;cache=_terrain_render_cache(imported,palette,catalog,archives);placements=[];minx=miny=2**31-1;maxx=maxy=-(2**31)
    for raw in imported.get('tiles',[]):
        tile=dict(raw);rx=int(tile['rx']);ry=int(tile['ry']);level=int(tile['level']);rendered=cache[(int(tile['tile_index']),int(tile['sub_tile']))];cx,cy=_project_cell(rx,ry,sw,level,baseline);left=cx-CELL_WIDTH//2+rendered.origin_x;top=cy-CELL_HEIGHT//2+rendered.origin_y;minx=min(minx,left);miny=min(miny,top);maxx=max(maxx,left+rendered.width);maxy=max(maxy,top+rendered.height);placements.append((cy,cx,left,top,rendered))
    if not placements:raise RA2MapError('Map contains no renderable IsoMapPack5 cells')
    minx-=4;miny-=4;maxx+=4;maxy+=4;width=maxx-minx;height=maxy-miny
    if width*height>120000000:raise RA2MapError(f'Rendered terrain canvas is unreasonably large: {width}x{height}')
    canvas=bytearray(width*height*4)
    for _,__,left,top,r in sorted(placements,key=lambda item:(item[0],item[1])):alpha_blit(canvas,width,height,r.rgba,r.width,r.height,left-minx,top-miny)
    return width,height,minx,miny,bytes(canvas)
def _read_shp_asset(archive,filename,palette,palette_name,prefix,limit):
    if not archive.has(filename):return []
    try:shp=ShpTsFile.from_bytes(archive.read(filename),source_name=filename)
    except ShpTsError as exc:raise RA2MapError(str(exc)) from exc
    return [AtlasAsset(f'{prefix}{frame.index:02d}',shp.width,shp.height,indexed_to_rgba(frame.pixels,shp.width,shp.height,palette),palette_name,filename,frame.index) for frame in shp.frames[:limit]]
def build_resource_atlas(archives,temperat_palette,unittem_palette):
    assets=[]
    for n in range(1,21):
        filename=f'tib{n:02d}.tem';loaded=_read_shp_asset(archives,filename,temperat_palette,'temperat.pal',f'tib_{n:02d}_',12)
        if not loaded:raise RA2MapError(f'Required ore overlay is missing: {filename}')
        assets.extend(loaded)
    for n in range(1,13):assets.extend(_read_shp_asset(archives,f'gem{n:02d}.tem',temperat_palette,'temperat.pal',f'gem_{n:02d}_',12))
    pillars=_read_shp_asset(archives,'tibtre01.tem',unittem_palette,'unittem.pal','tibtre01_',11)
    if not pillars:raise RA2MapError('Required ore pillar overlay is missing: tibtre01.tem')
    assets.extend(pillars);slotw=max(a.width for a in assets)+2;sloth=max(a.height for a in assets)+2;cols=max(1,min(len(assets),2048//slotw));rows=math.ceil(len(assets)/cols);width=cols*slotw;height=rows*sloth;canvas=bytearray(width*height*4);manifest={}
    for index,a in enumerate(assets):
        left=(index%cols)*slotw+(slotw-a.width)//2;top=(index//cols)*sloth+sloth-a.height-1;alpha_blit(canvas,width,height,a.rgba,a.width,a.height,left,top);manifest[a.asset_id]={'region':[left,top,a.width,a.height],'anchor':[a.width/2.0,a.height-1.0],'palette':a.palette_name,'source':a.source_name,'frame':a.frame}
    return width,height,bytes(canvas),manifest
def encode_cell_records(imported):
    output=bytearray()
    for raw in imported.get('tiles',[]):
        tile=dict(raw);theater=dict(tile.get('theater',{}));output+=CELL_STRUCT.pack(int(tile['rx']),int(tile['ry']),int(tile['level']),int(theater.get('terrain_type',0)),int(theater.get('ramp_type',0)))
    return bytes(output)
def overlay_kind(overlay_id):return 1 if ORE_ID_FIRST<=overlay_id<=ORE_ID_LAST else 2 if GEM_ID_FIRST<=overlay_id<=GEM_ID_LAST else 0
def encode_resource_records(imported):
    output=bytearray();count=0
    for raw in imported.get('overlays',[]):
        overlay=dict(raw);oid=int(overlay['overlay_id']);kind=overlay_kind(oid)
        if not kind:continue
        output+=RESOURCE_STRUCT.pack(int(overlay['rx']),int(overlay['ry']),oid,int(overlay['frame']),kind);count+=1
    return bytes(output),count
def _positions(imported):
    result=[]
    for raw in sorted(imported.get('waypoints',[]),key=lambda value:int(value['id'])):
        ident=int(raw['id'])
        if 0<=ident<=7:result.append([int(raw['rx']),int(raw['ry'])])
    return result
def _terrain_objects(imported,prefix):return [{'cell':[int(raw['rx']),int(raw['ry'])],'type':str(raw.get('type',''))} for raw in imported.get('terrain',[]) if str(raw.get('type','')).upper().startswith(prefix.upper())]
def _sha256(path):
    digest=hashlib.sha256()
    with path.open('rb') as handle:
        for block in iter(lambda:handle.read(1024*1024),b''):digest.update(block)
    return digest.hexdigest()
def _write_json(path,data):path.parent.mkdir(parents=True,exist_ok=True);path.write_text(json.dumps(data,ensure_ascii=False,indent=2)+'\n',encoding='utf-8')
def _res_template(relative_dir,stem):return f"res://{relative_dir.strip('/')}/{stem}_%02d.b64"
def build_bundle(arguments):
    source_map=arguments.source_map;theater_ini=arguments.theater_ini;theater_paths=[arguments.isotemp]
    if arguments.temperat is not None:theater_paths.append(arguments.temperat)
    imported=import_map(source_map);catalog=TheaterCatalog.from_path(theater_ini,arguments.theater_extension);archives=ArchiveStack(CaseInsensitiveZip(path) for path in theater_paths)
    try:
        imported=enrich_imported_map(imported,catalog,archives);isotem_palette=load_palette(arguments.isotem_palette);temperat_palette=load_palette(arguments.temperat_palette);unittem_palette=load_palette(arguments.unittem_palette);tw,th,cropx,cropy,trgba=render_terrain(imported,isotem_palette,catalog,archives);tpng=encode_png_rgba(tw,th,trgba);rw,rh,rrgba,rassets=build_resource_atlas(archives,temperat_palette,unittem_palette);rpng=encode_png_rgba(rw,rh,rrgba)
    finally:archives.close()
    root=arguments.project_root.resolve();mapout=root/arguments.map_output_dir;embout=root/arguments.embedded_output_dir;mapout.mkdir(parents=True,exist_ok=True);embout.mkdir(parents=True,exist_ok=True);stem=arguments.map_stem or source_map.stem.lower();catalog_path=root/arguments.map_catalog;catalog_data={}
    if catalog_path.exists():
        parsed=json.loads(catalog_path.read_text(encoding='utf-8'))
        if not isinstance(parsed,dict):raise RA2MapError(f'Map catalog must be a JSON object: {catalog_path}')
        catalog_data=parsed
    positions=_positions(imported)
    if not positions:
        existing=catalog_data.get(arguments.map_id,{})
        raw_positions=existing.get('positions',[]) if isinstance(existing,dict) else []
        if isinstance(raw_positions,list):positions=[[int(value[0]),int(value[1])] for value in raw_positions if isinstance(value,list) and len(value)>=2]
    cell_payload=encode_cell_records(imported);cell_chunks=write_base64_chunks(cell_payload,mapout,f'{stem}_cells');terrain_chunks=write_base64_chunks(tpng,mapout,f'{stem}_terrain');resource_chunks=write_base64_chunks(rpng,embout,'temperate_resources_v2');resource_payload,resource_count=encode_resource_records(imported);sw=int(imported['map']['width']);sh=int(imported['map']['height']);levels=[int(tile['level']) for tile in imported['tiles']]
    runtime={'format':'ra2-godot-runtime-v2','source_map':source_map.name,'source_name':source_map.name,'map_name':str(imported.get('basic',{}).get('Name',source_map.stem)),'theater':str(imported['map']['theater']),'source_size':[sw,sh],'logical_size':[sw*2,sh*2],'local_size':imported['map']['local_size'],'cell_size':[CELL_WIDTH,CELL_HEIGHT],'cell_height':HEIGHT_STEP,'max_height':max(levels,default=0),'baseline':sw*(CELL_HEIGHT//2)+180,'render_crop':[cropx,cropy],'render_size':[tw,th],'background':{'chunk_template':_res_template(arguments.map_output_dir,f'{stem}_terrain'),'chunk_count':terrain_chunks,'format':'png','sha256':hashlib.sha256(tpng).hexdigest()},'cells':{'chunk_template':_res_template(arguments.map_output_dir,f'{stem}_cells'),'chunk_count':cell_chunks,'record_format':'<HHBBB','record_size':CELL_STRUCT.size,'count':len(imported['tiles']),'sha256':hashlib.sha256(cell_payload).hexdigest()},'resources':{'encoded':base64.b64encode(resource_payload).decode('ascii'),'record_format':'<HHHBB','record_size':RESOURCE_STRUCT.size,'count':resource_count},'positions':positions,'trees':_terrain_objects(imported,'TREE'),'ore_pillars':_terrain_objects(imported,'TIBTRE'),'provenance':{'canonical_map':{'name':source_map.name,'sha256':_sha256(source_map)},'theater_ini':{'name':theater_ini.name,'sha256':_sha256(theater_ini)},'theater_archives':[{'name':path.name,'sha256':_sha256(path)} for path in theater_paths],'palettes':{'terrain':{'name':arguments.isotem_palette.name,'sha256':_sha256(arguments.isotem_palette)},'resources':{'name':arguments.temperat_palette.name,'sha256':_sha256(arguments.temperat_palette)},'pillar':{'name':arguments.unittem_palette.name,'sha256':_sha256(arguments.unittem_palette)}}}}
    runtime_path=mapout/f'{stem}_runtime.json';_write_json(runtime_path,runtime);resource_manifest={'format':'ra2-resource-atlas-v2','image_format':'png','chunk_template':_res_template(arguments.embedded_output_dir,'temperate_resources_v2'),'chunk_count':resource_chunks,'size':[rw,rh],'sha256':hashlib.sha256(rpng).hexdigest(),'assets':rassets,'palette_rules':{'TIB*.TEM':'temperat.pal','GEM*.TEM':'temperat.pal','TIBTRE*.TEM':'unittem.pal'}};resource_manifest_path=embout/'temperate_resources_v2.json';_write_json(resource_manifest_path,resource_manifest);relative_runtime=runtime_path.relative_to(root).as_posix();catalog_data[arguments.map_id]={'name':arguments.map_name or runtime['map_name'],'description':'由原始 RA2/YR 地图、IsoMapPack5、Temperat.ini 与 TMP 构建的 60×30 等距运行时地图。','format':'ra2_runtime_v2','runtime_manifest':f'res://{relative_runtime}','canonical_source':source_map.name,'size':runtime['logical_size'],'positions':positions,'tree_density':0.0,'force_disable_fog':bool(arguments.force_disable_fog)};_write_json(catalog_path,catalog_data)
    return {'runtime_manifest':runtime_path,'resource_manifest':resource_manifest_path,'terrain_size':[tw,th],'cell_count':len(imported['tiles']),'resource_count':resource_count,'spawn_count':len(positions)}
def create_parser():
    parser=argparse.ArgumentParser(description='Build Godot RA2 runtime map and correctly-paletted resource bundles');parser.add_argument('source_map',type=Path);parser.add_argument('--theater-ini',type=Path,required=True);parser.add_argument('--isotemp',type=Path,required=True);parser.add_argument('--temperat',type=Path);parser.add_argument('--isotem-palette',type=Path,required=True);parser.add_argument('--temperat-palette',type=Path,required=True);parser.add_argument('--unittem-palette',type=Path,required=True);parser.add_argument('--theater-extension',default='.tem');parser.add_argument('--project-root',type=Path,default=Path.cwd());parser.add_argument('--map-output-dir',default='data/ra2_maps');parser.add_argument('--embedded-output-dir',default='data/ra2_embedded');parser.add_argument('--map-catalog',default='data/maps_ra2.json');parser.add_argument('--map-id',default='ra2_mymap1');parser.add_argument('--map-name');parser.add_argument('--map-stem');parser.add_argument('--force-disable-fog',action='store_true');return parser
def main():
    parser=create_parser();arguments=parser.parse_args()
    try:result=build_bundle(arguments)
    except (OSError,ValueError,json.JSONDecodeError,RA2MapError) as exc:parser.error(str(exc))
    print(f"Built RA2 runtime bundle: {result['cell_count']} cells, {result['resource_count']} resource overlays, terrain {result['terrain_size'][0]}x{result['terrain_size'][1]}, {result['spawn_count']} spawns");print(f"Runtime manifest: {result['runtime_manifest']}");print(f"Resource manifest: {result['resource_manifest']}");return 0
if __name__=='__main__':raise SystemExit(main())
