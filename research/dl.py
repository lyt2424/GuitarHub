import urllib.request, os
urls = {
 "pulze_midi_en_v106.pdf": "https://res.hotoneaudio.com/prod/support/Pulze%20MIDI%20Control%20Information%20List_EN_Firmware%20V1.0.6.1701218099204.pdf",
 "pulze_midi_ru_v106.pdf": "https://hotoneaudio.ru/upload/iblock/cb3/wa30ty0qx4skxw7nu3f1vnj4bbfdvo8k/Pulze-MIDI-Control-Information-List_RU_Firmware-V1.0.6.pdf",
 "pulze_manual_en.pdf": "https://www.hotone.jp/manuals/hotone/PULZE.pdf",
 "pulze_mini_manual_jp.pdf": "https://www.hotone.jp/manuals/hotone/PULZE%20MINI_AP-5WH.pdf",
 "pulze_control_manual_jp.pdf": "http://allaccess.co.jp/hotone/pulzecontrol/doc/PulzeControl_Manual_JP.pdf",
}
hdr={"User-Agent":"Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 Chrome/124 Safari/537.36"}
for name,u in urls.items():
    p=os.path.join("research","pdf",name)
    try:
        req=urllib.request.Request(u,headers=hdr)
        d=urllib.request.urlopen(req,timeout=90).read()
        open(p,"wb").write(d)
        print("OK",name,len(d),d[:5])
    except Exception as e:
        print("FAIL",name,type(e).__name__,e)
