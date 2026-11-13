"""Check exported GLB/WAV structure and required animation contracts without a GPU."""
from pathlib import Path
import json, math, struct, wave

ROOT=Path(__file__).resolve().parents[1]
MODELS=ROOT/'assets'/'models'/'characters'
required={
    'fang_chen':['Idle','Walk','Run','Attack1','Attack2','Attack3','Energy','Piercing','Guard','Mend','Dodge','Hit','Death','Bind'],
    'cao_bin':['Idle'],
    'boar':['Idle','Walk','Attack','Hit','Death'],
    'mountain_wolf':['Idle','Walk','Attack','Hit','Death'],
    'bamboo_beast':['Idle','Walk','Attack','Heavy','Hit','Death'],
    'linglong_bamboo':[],
}
for name,clips in required.items():
    path=MODELS/(name+'.glb'); data=path.read_bytes()
    assert data[:4]==b'glTF' and struct.unpack_from('<II',data,4)==(2,len(data)), path
    length,kind=struct.unpack_from('<II',data,12)
    assert kind==0x4E4F534A
    gltf=json.loads(data[20:20+length]); animations=gltf.get('animations',[])
    names={a['name'] for a in animations}
    assert set(clips)==names, (path,names)
    assert len(gltf['scenes'])==1
    triangles=0
    for mesh in gltf['meshes']:
        for primitive in mesh['primitives']:
            assert primitive.get('mode',4)==4
            triangles+=gltf['accessors'][primitive['indices']]['count']//3
            if clips:
                assert 'JOINTS_0' in primitive['attributes'] and 'WEIGHTS_0' in primitive['attributes']
    assert triangles<15000, (path,triangles)
    if clips:
        assert gltf['skins'] and all(len(s['joints'])>=7 for s in gltf['skins'])
    for animation in animations:
        assert animation['channels']
        for sampler in animation['samplers']:
            accessor=gltf['accessors'][sampler['input']]
            assert accessor['count']>=2 and accessor['max'][0]>accessor['min'][0]
    for accessor in gltf['accessors']:
        for field in ['min','max']:
            assert all(math.isfinite(v) for v in accessor.get(field,[]))
    print(f'{name}: {triangles} triangles, {len(names)} clips, {len(data)} bytes')
for name in ['qianzhu_theme','bamboo_battle','swing','hit','windup','hurt','energy','pickup','heal','level_up','ui_confirm']:
    path=ROOT/'assets'/'audio'/(name+'.wav')
    with wave.open(str(path),'rb') as f:
        assert (f.getnchannels(),f.getsampwidth(),f.getframerate())==(1,2,22050)
        assert f.getnframes()>0
        samples=struct.unpack('<'+'h'*f.getnframes(),f.readframes(f.getnframes()))
        assert max(map(abs,samples))<32767 and max(map(abs,samples))>1000
        print(f'{name}: {len(samples)/22050:.2f}s PCM')
font=ROOT/'assets'/'fonts'/'NotoSansCJKsc-Regular.otf'
assert font.read_bytes()[:4]==b'OTTO'
assert 'SIL OPEN FONT LICENSE' in (font.parent/'OFL.txt').read_text()
print('ASSET_CONTRACT_PASS')
