"""Generate original PCM music and sound effects. No third-party recordings."""
from pathlib import Path
import array, math, random, wave

ROOT=Path(__file__).resolve().parents[1]
OUT=ROOT/'assets'/'audio'
OUT.mkdir(parents=True,exist_ok=True)
RATE=22050

def save(name, samples):
    peak=max(max(abs(x) for x in samples),.001)
    data=array.array('h',(round(x/peak*.72*32767) for x in samples))
    with wave.open(str(OUT/(name+'.wav')),'wb') as f:
        f.setnchannels(1); f.setsampwidth(2); f.setframerate(RATE); f.writeframes(data.tobytes())

def note(midi): return 440*2**((midi-69)/12)

def music(name,battle):
    seconds=16
    samples=[0.0]*(RATE*seconds)
    phrase=[60,64,67,69,67,64,62,60,55,60,62,64,67,64,62,55]
    for step in range(32):
        f=note(phrase[step%16]-(12 if battle else 0))
        for j in range(int(RATE*1.8)):
            i=step*RATE//2+j
            if i>=len(samples): break
            t=j/RATE
            envelope=(1-math.exp(-t*140))*math.exp(-t*(4.5 if battle else 2.7))
            tone=math.sin(2*math.pi*f*t)+.28*math.sin(2*math.pi*f*2*t)+.08*math.sin(2*math.pi*f*3*t)
            samples[i]+=tone*envelope*.28
        if battle:
            for j in range(RATE//5):
                i=step*RATE//2+j
                t=j/RATE
                samples[i]+=.35*math.sin(2*math.pi*(70*t-55*t*t))*math.exp(-t*22)
    # Gentle loop boundaries rather than clicks.
    for i in range(RATE//30):
        fade=i/(RATE//30)
        samples[i]*=fade; samples[-1-i]*=fade
    save(name,samples)

music('qianzhu_theme',False)
music('bamboo_battle',True)
rng=random.Random(7331)
for name,kind,duration in [('swing',0,.18),('hit',1,.15),('windup',2,.35),('hurt',3,.22),
    ('energy',4,.6),('pickup',5,.24),('heal',6,.45),('level_up',7,.65),('ui_confirm',8,.10)]:
    values=[]
    for i in range(int(RATE*duration)):
        t=i/RATE; x=t/duration
        envelope=math.sin(math.pi*x)**.8*(1-x)
        if kind==0: value=rng.uniform(-1,1)*.8+math.sin(2*math.pi*(1100*t-2200*t*t))*.15
        elif kind==1: value=rng.uniform(-1,1)*math.exp(-x*5)+.4*math.sin(2*math.pi*180*t)
        elif kind==2: value=math.sin(2*math.pi*(180*t+300*t*t))
        elif kind==3: value=math.sin(2*math.pi*(210*t-180*t*t))+.3*rng.uniform(-1,1)
        elif kind==4: value=.5*rng.uniform(-1,1)+math.sin(2*math.pi*(280*t+700*t*t))*.4
        elif kind==5: value=math.sin(2*math.pi*(880 if x<.5 else 1320)*t)
        elif kind==6: value=math.sin(2*math.pi*(440*t+350*t*t))
        elif kind==7: value=math.sin(2*math.pi*note([60,64,67,72][min(3,int(x*4))])*t)
        else: value=math.sin(2*math.pi*660*t)
        values.append(value*envelope)
    save(name,values)
print('AUDIO_EXPORTED',len(list(OUT.glob('*.wav'))))
