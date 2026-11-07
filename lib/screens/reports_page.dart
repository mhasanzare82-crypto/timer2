import 'dart:convert';
import 'dart:io';
import 'package:archive/archive.dart';
import 'package:excel/excel.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:persian_datetime_picker/persian_datetime_picker.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';
import '../database/app_database.dart';
import '../models/time_record.dart';
import '../utils/time_formatter.dart';

class ReportsPage extends StatefulWidget {
 const ReportsPage({super.key});
 @override State<ReportsPage> createState()=>_ReportsPageState();
}
class _ReportsPageState extends State<ReportsPage> {
 List<TimeRecord> all=[], rows=[]; List<String> names=[];
 String period='روزانه', activity='همه فعالیت‌ها'; DateTimeRange? range; bool loading=true;
 @override void initState(){super.initState();load();}
 Future<void> load() async {
  final r=await AppDatabase.instance.getAllRecords(); final n=r.map((e)=>e.title).toSet().toList()..sort();
  if(!mounted)return; setState(()=>{all=r,names=n,loading=false}); apply();
 }
 DateTimeRange get bounds {
  final now=DateTime.now(); if(period=='بازه دلخواه'&&range!=null)return range!;
  if(period=='هفتگی'){final s=DateTime(now.year,now.month,now.day).subtract(Duration(days:now.weekday-1));return DateTimeRange(start:s,end:s.add(const Duration(days:7)));}
  if(period=='ماهانه')return DateTimeRange(start:DateTime(now.year,now.month),end:DateTime(now.year,now.month+1));
  final s=DateTime(now.year,now.month,now.day);return DateTimeRange(start:s,end:s.add(const Duration(days:1)));
 }
 void apply(){final b=bounds; final r=all.where((e)=>!e.activityDate.isBefore(b.start)&&e.activityDate.isBefore(b.end)&&(activity=='همه فعالیت‌ها'||e.title==activity)).toList();if(mounted)setState(()=>rows=r);}
 int get total=>rows.fold(0,(s,e)=>s+e.durationSeconds);
 Future<void> chooseRange() async {
  final now = Jalali.now();
  final current = range;
  final selected = await showPersianDateRangePicker(
    context: context,
    initialDateRange: JalaliRange(
      start: current == null ? now.subtract(const Duration(days: 6)) : Jalali.fromDateTime(current.start),
      end: current == null ? now : Jalali.fromDateTime(current.end.subtract(const Duration(days: 1))),
    ),
    firstDate: Jalali(1300, 1),
    lastDate: Jalali(1500, 12),
    helpText: 'انتخاب بازه شمسی',
    cancelText: 'انصراف',
    confirmText: 'تأیید',
    locale: const Locale('fa', 'IR'),
    textDirection: TextDirection.rtl,
  );
  if (selected != null) {
    final startDate = selected.start.toDateTime();
    final endDate = selected.end.toDateTime().add(const Duration(days: 1));
    setState(() => range = DateTimeRange(start: startDate, end: endDate));
    apply();
  }
 }

 Future<File> temp(String name,List<int> bytes)async{final d=await getTemporaryDirectory();return File('${d.path}/$name').writeAsBytes(bytes,flush:true);}
 Future<void> excelExport()async{
  final x=Excel.createExcel(),s=x['گزارش فعالیت'];s.appendRow(['عنوان','دسته‌بندی','تاریخ شمسی','مدت (ثانیه)','مدت','یادداشت'].map((e)=>TextCellValue(e)).toList());
  for(final r in rows){s.appendRow([TextCellValue(r.title),TextCellValue(r.category),TextCellValue(TimeFormatter.jalaliDateTime(r.activityDate)),IntCellValue(r.durationSeconds),TextCellValue(TimeFormatter.format(r.durationSeconds)),TextCellValue(r.note??'')]);}
  final bytes=x.encode();if(bytes==null)return;final f=await temp('gozaresh.xlsx',bytes);await Share.shareXFiles([XFile(f.path)],text:'گزارش فعالیت‌ها');
 }
 Future<void> backup()async{
  final data={'format':'timer2-backup','version':1,'records':all.map((r)=>{'title':r.title,'category':r.category,'durationSeconds':r.durationSeconds,'createdAt':r.createdAt.millisecondsSinceEpoch,'activityDate':r.activityDate.millisecondsSinceEpoch,'note':r.note}).toList()};
  final raw=utf8.encode(const JsonEncoder.withIndent('  ').convert(data));final a=Archive()..addFile(ArchiveFile('backup.json',raw.length,raw));
  final x=Excel.createExcel(),s=x['Activities'];s.appendRow(['title','category','durationSeconds','createdAt','activityDate','note'].map((e)=>TextCellValue(e)).toList());
  for(final r in all){s.appendRow([TextCellValue(r.title),TextCellValue(r.category),IntCellValue(r.durationSeconds),IntCellValue(r.createdAt.millisecondsSinceEpoch),IntCellValue(r.activityDate.millisecondsSinceEpoch),TextCellValue(r.note??'')]);}
  final xb=x.encode();if(xb!=null)a.addFile(ArchiveFile('activities.xlsx',xb.length,xb));
  final z=ZipEncoder().encode(a);final f=await temp('timer2_backup.zip',z);await Share.shareXFiles([XFile(f.path)],text:'پشتیبان قابل بازیابی timer2');
 }
 Future<void> restore()async{
  final p=await FilePicker.platform.pickFiles(type:FileType.custom,allowedExtensions:['zip']);if(p==null||p.files.single.path==null)return;
  try{
   final a=ZipDecoder().decodeBytes(await File(p.files.single.path!).readAsBytes());final e=a.files.firstWhere((x)=>x.name=='backup.json');final d=jsonDecode(utf8.decode(e.content as List<int>)) as Map<String,dynamic>;
   if(d['format']!='timer2-backup'||d['version']!=1)throw Exception('bad backup');
   final list=(d['records'] as List).cast<Map<String,dynamic>>();
   final ok=await showDialog<bool>(context:context,builder:(c)=>AlertDialog(title:const Text('بازیابی پشتیبان'),content:Text('${list.length} فعالیت پیدا شد. به اطلاعات فعلی اضافه شوند؟'),actions:[TextButton(onPressed:()=>Navigator.pop(c,false),child:const Text('انصراف')),FilledButton(onPressed:()=>Navigator.pop(c,true),child:const Text('بازیابی'))]));
   if(ok!=true)return;
   for(final m in list){await AppDatabase.instance.insertRecord(TimeRecord(title:m['title'],category:m['category'],durationSeconds:(m['durationSeconds'] as num).toInt(),createdAt:DateTime.fromMillisecondsSinceEpoch((m['createdAt'] as num).toInt()),activityDate:DateTime.fromMillisecondsSinceEpoch((m['activityDate'] as num).toInt()),note:m['note'] as String?));}
   await load();if(mounted)ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content:Text('بازیابی انجام شد.')));
  }catch(_){if(mounted)ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content:Text('فایل پشتیبان معتبر نیست.')));}
 }
 @override Widget build(BuildContext context){
  if(loading)return const Center(child:CircularProgressIndicator());final b=bounds;
  return ListView(padding:const EdgeInsets.all(16),children:[
   const Text('گزارش‌گیری',style:TextStyle(fontSize:23,fontWeight:FontWeight.bold)),const SizedBox(height:14),
   DropdownButtonFormField<String>(value:period,decoration:const InputDecoration(labelText:'دوره گزارش',border:OutlineInputBorder()),items:['روزانه','هفتگی','ماهانه','بازه دلخواه'].map((v)=>DropdownMenuItem(value:v,child:Text(v))).toList(),onChanged:(v){if(v!=null){setState(()=>period=v);if(v=='بازه دلخواه')chooseRange();else apply();}}),
   if(period=='بازه دلخواه')ListTile(title:const Text('انتخاب بازه'),subtitle:Text(range==null?'انتخاب نشده':'${TimeFormatter.jalaliDate(range!.start)} تا ${TimeFormatter.jalaliDate(range!.end)}'),trailing:const Icon(Icons.date_range),onTap:chooseRange),
   const SizedBox(height:10),
   DropdownButtonFormField<String>(value:activity,decoration:const InputDecoration(labelText:'فعالیت',border:OutlineInputBorder()),items:['همه فعالیت‌ها',...names].map((v)=>DropdownMenuItem(value:v,child:Text(v,overflow:TextOverflow.ellipsis))).toList(),onChanged:(v){if(v!=null){setState(()=>activity=v);apply();}}),
   Card(child:Padding(padding:const EdgeInsets.all(18),child:Column(children:[const Text('مجموع زمان'),Text(TimeFormatter.format(total),style:const TextStyle(fontSize:26,fontWeight:FontWeight.bold,color:Colors.indigo)),Text('${rows.length} رکورد • ${TimeFormatter.jalaliDate(b.start)} تا ${TimeFormatter.jalaliDate(b.end.subtract(const Duration(days:1)))}')]))),
   FilledButton.icon(onPressed:excelExport,icon:const Icon(Icons.table_view),label:const Text('خروجی اکسل')),
   OutlinedButton.icon(onPressed:backup,icon:const Icon(Icons.archive),label:const Text('خروجی پشتیبان ZIP')),
   OutlinedButton.icon(onPressed:restore,icon:const Icon(Icons.restore),label:const Text('وارد کردن پشتیبان ZIP')),
   const SizedBox(height:12),const Text('جزئیات فعالیت‌ها',style:TextStyle(fontWeight:FontWeight.bold)),
   ...rows.map((r)=>ListTile(contentPadding:EdgeInsets.zero,title:Text(r.title),subtitle:Text('${TimeFormatter.jalaliDateTime(r.activityDate)} • ${TimeFormatter.format(r.durationSeconds)}'))),
   if(rows.isEmpty)const Padding(padding:EdgeInsets.all(24),child:Center(child:Text('در این بازه فعالیتی ثبت نشده است.')))
  ]);
 }
}
