"""Render example reading aids using curriculum spellings and explicit words.

This is a closed curriculum lexicon, not a general Thai transliterator. Unknown
words fail generation so new examples require a reviewed spelling.
"""

EXTRA = dict(line.split('=', 1) for line in '''กรุงเทพ=krung thep
กลิ่น=klin
กว่า=kwa
กัน=kan
การ=kan
กำลัง=kamlang
กิโลเมตร=kilomet
ขอ=kho
ของ=khong
ขับ=khap
ข้าง=khang
ครอบครัว=khrop khrua
คัน=khan
คือ=khue
คู่=khu
งาน=ngan
จะ=cha
จันทร์=chan
จาก=chak
ชั้น=chan
ช้าๆ=cha cha
ซุป=sup
ดี=di
ด้วย=duai
ด้วยกัน=duai kan
ด้าน=dan
ตรง=trong
ตรวจ=truat
ตอน=ton
ตัว=tua
ติด=tit
ติดขัด=tit khat
ต้องการ=tongkan
ถ่าย=thai
ทัน=than
ที่=thi
ที่ไหน=thi nai
ทุก=thuk
ทุ่ม=thum
นาน=nan
นี่=ni
นี้=ni
น้อยๆ=noi noi
บอก=bok
บิล=bin
บ้าง=bang
บ้าน=ban
ป้าย=pai
พฤหัสบดี=pharuehatsabodi
พัก=phak
พุธ=phut
ฟอง=fong
มะนาว=manao
มิน=min
รหัส=rahat
รับ=rap
ลด=lot
ลา=la
ว่าง=wang
ศุกร์=suk
สด=sot
สวย=suai
สอบ=sop
สีน้ำเงิน=si nam ngoen
สุก=suk
หน่อย=noi
หน้า=na
หาย=hai
อย่างไร=yang rai
อะไร=arai
อังคาร=angkhan
อัน=an
อากาศ=akat
อาทิตย์=athit
อายุ=ayu
อื่น=uen
เจ=che
เชียงใหม่=chiang mai
เช็ก=chek
เช่า=chao
เดินทาง=doen thang
เปอร์เซ็นต์=poesen
เป็น=pen
เพลง=phleng
เพิ่ม=phoem
เมตร=met
เยอะ=yoe
เยอะๆ=yoe yoe
เย็นๆ=yen yen
เรียก=riak
เลข=lek
เลิก=loek
เล่น=len
เสาร์=sao
เสื้อผ้า=suea pha
เอ็ด=et
แป๊บ=paep
แยก=yaek
แรง=raeng
แล้ว=laeo
ใจดี=chai di
ใต้ดิน=tai din
ใน=nai
ใบ=bai
ใส่=sai
ไซซ์=sai
ไต้หวัน=taiwan
ไม่=mai
ไม่มี=mai mi
ไว้=wai
ไหน=nai
ไหม=mai
ค่ะ=khâ
คะ=khá
เกลือ=kluea'''.splitlines())


def add_example_romanization(data):
    lexicon = {item['thai']: item['romanization'] for item in data['vocabulary']}
    lexicon.update(EXTRA)
    for item in data['vocabulary']:
        for variant in (item, item.get('female', {})):
            text = variant.get('example_thai')
            if text:
                words = text.replace('เก ลือ', 'เกลือ').split()
                variant['example_romanization'] = ' '.join(lexicon[word] for word in words)
