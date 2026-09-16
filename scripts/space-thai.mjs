// Build beginner-friendly word spacing while preserving original speech text.
// Intl.Segmenter uses ICU's Thai dictionary. Protect established loanwords and
// compound vocabulary that ICU can split incorrectly; never split Thai marks.
import fs from 'node:fs';
import {createHash} from 'node:crypto';
const segmenter = new Intl.Segmenter('th', {granularity:'word'});
const protectedWords = [
  'เช็กเอาต์','เช็กอิน','เช็ก','ต้องการ','กรุงเทพ','หนังสือเดินทาง','ผ้าเช็ดตัว',
  'ทำความสะอาด','สนามบิน','เที่ยวบิน','โรงพยาบาล','รถพยาบาล','สถานทูต',
  'ข้าวผัด','ผัดไทย','น้ำเปล่า','น้ำแข็ง','อาหารเช้า','ใบเสร็จ','บัตรเครดิต',
  'สบายดี','นิดหน่อย','ด้วยกัน','วันนี้','เวลา','ไม่เป็นไร','ขอบคุณ','ขอโทษ',
  'พรุ่งนี้','เมื่อวาน','ตอนนี้','กลางคืน','ผลไม้','ร้านอาหาร','เครื่องบิน','ค่าโดยสาร','ระยะทาง','การจราจร','นักท่องเที่ยว','เดินทาง','สถานที่','ทางเข้า','ข้าวมันไก่',
  'เท่าไร','ที่ไหน','มังสวิรัติ','ไต้หวัน','มิเตอร์','เคาน์เตอร์','ไวไฟ',
].sort((a,b)=>b.length-a.length);
const pattern = new RegExp(`(${protectedWords.join('|')})`, 'gu');
function spaced(text) {
  return text.split(pattern).filter(Boolean).flatMap(part => protectedWords.includes(part) ? [part] : [...segmenter.segment(part)].map(s=>s.segment.trim()).filter(Boolean)).join(' ').replaceAll('ขอดู', 'ขอ ดู');
}
const path = 'thai_practice_dataset.json';
const data = JSON.parse(fs.readFileSync(path, 'utf8'));
for (const item of [...data.vocabulary, ...data.sentences]) {
  item.thai_native ??= item.thai;
  item.thai = spaced(item.thai_native);
  if(item.example_thai){item.example_thai_native ??= item.example_thai;item.example_thai=spaced(item.example_thai_native);}
  if(item.thai.replaceAll(' ','')!==item.thai_native.replaceAll(' ','')) throw Error(`Changed Thai content: ${item.id}`);
}
const output = JSON.stringify(data, null, 2)+'\n';
fs.writeFileSync(path, output);
fs.writeFileSync('assets/data/'+path, output);
fs.writeFileSync(path+'.sha256', createHash('sha256').update(output).digest('hex')+'  '+path+'\n');
console.log('Updated 400 items and examples; native Thai preserved for speech.');
