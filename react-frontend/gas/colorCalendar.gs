/**
 * カレンダー書式設定スクリプト
 *
 * メニュー:
 *   「全シート一括設定」 → 全YYYYMMシートをリセット＋日付生成＋条件付き書式
 *   「このシートのみ設定」 → アクティブシートだけ実行
 */

var DOW_NAMES = ['日', '月', '火', '水', '木', '金', '土'];

function getHolidayDays(month) {
  switch (month) {
    case 1:  return [1, 13];
    case 2:  return [11, 23];
    case 3:  return [20];
    case 4:  return [29];
    case 5:  return [3, 4, 5, 6];
    case 7:  return [20];
    case 8:  return [11];
    case 9:  return [21, 22, 23];
    case 10: return [12];
    case 11: return [3, 23];
    default: return [];
  }
}

function parseSheetName(name) {
  var match = name.match(/^(\d{4})(\d{2})$/);
  if (!match) return null;
  return { year: parseInt(match[1], 10), month: parseInt(match[2], 10) };
}

function getDaysInMonth(year, month) {
  return new Date(year, month, 0).getDate();
}

/**
 * 1シートをフル設定（リセット→日付→書式）
 */
function setupSheet(sheet) {
  var parsed = parseSheetName(sheet.getName());
  if (!parsed) return null;

  var year = parsed.year;
  var month = parsed.month;
  var lastRow = sheet.getLastRow();

  // --- リセット ---
  sheet.clearConditionalFormatRules();
  if (lastRow >= 3) {
    var clearRange = sheet.getRange(3, 1, lastRow - 2, 19);
    clearRange.setFontColor('#000000');
    clearRange.setBackground('#ffffff');
  }

  // --- タイトル・ヘッダー ---
  sheet.getRange(1, 2).setValue(year + '年' + month + '月作業予定');

  // 既存シートから2行目をコピー
  var ss = SpreadsheetApp.getActiveSpreadsheet();
  var sheets = ss.getSheets();
  for (var s = 0; s < sheets.length; s++) {
    if (sheets[s].getName() === sheet.getName()) continue;
    if (parseSheetName(sheets[s].getName())) {
      sheet.getRange(2, 1, 1, 19).setValues(sheets[s].getRange(2, 1, 1, 19).getValues());
      break;
    }
  }

  // --- 日付・曜日を書き込み ---
  var daysInMonth = getDaysInMonth(year, month);
  var dateCols = [2, 5, 8, 11, 14, 17];
  var dowCols  = [3, 6, 9, 12, 15, 18];

  for (var day = 1; day <= daysInMonth; day++) {
    var row = day + 2;
    var date = new Date(year, month - 1, day);
    var dowName = DOW_NAMES[date.getDay()];
    for (var c = 0; c < dateCols.length; c++) {
      sheet.getRange(row, dateCols[c]).setValue(day);
      sheet.getRange(row, dowCols[c]).setValue(dowName);
    }
  }

  // --- 条件付き書式 ---
  var holidayDays = getHolidayDays(month);
  var rules = [];
  var LR = 100;

  var pairRanges = [
    ['B', 'C'], ['E', 'F'], ['H', 'I'],
    ['K', 'L'], ['N', 'O'], ['Q', 'R']
  ];

  for (var i = 0; i < pairRanges.length; i++) {
    var dc = pairRanges[i][0];
    var dw = pairRanges[i][1];
    var range = sheet.getRange(dc + '3:' + dw + LR);

    rules.push(SpreadsheetApp.newConditionalFormatRule()
      .whenFormulaSatisfied('=$' + dw + '3="土"').setFontColor('#0000ff').setRanges([range]).build());

    rules.push(SpreadsheetApp.newConditionalFormatRule()
      .whenFormulaSatisfied('=$' + dw + '3="日"').setFontColor('#ff0000').setRanges([range]).build());

    if (holidayDays.length > 0) {
      var parts = [];
      for (var h = 0; h < holidayDays.length; h++) {
        parts.push('$' + dc + '3=' + holidayDays[h]);
      }
      rules.push(SpreadsheetApp.newConditionalFormatRule()
        .whenFormulaSatisfied('=OR(' + parts.join(',') + ')').setFontColor('#ff0000').setRanges([range]).build());
    }
  }

  var offCols = [['D','B','D'], ['G','E','G'], ['J','H','J'], ['M','K','M'], ['P','N','P']];
  for (var o = 0; o < offCols.length; o++) {
    var ck = offCols[o][0];
    var bgRange = sheet.getRange(offCols[o][1] + '3:' + offCols[o][2] + LR);

    rules.push(SpreadsheetApp.newConditionalFormatRule()
      .whenFormulaSatisfied('=OR($' + ck + '3="定休日",ISNUMBER(SEARCH("休",$' + ck + '3)))')
      .setBackground('#ffcccc').setRanges([bgRange]).build());

    rules.push(SpreadsheetApp.newConditionalFormatRule()
      .whenFormulaSatisfied('=ISNUMBER(SEARCH("リモート",$' + ck + '3))')
      .setBackground('#ccffcc').setRanges([bgRange]).build());
  }

  sheet.setConditionalFormatRules(rules);
  return year + '年' + month + '月';
}

/**
 * 全シート一括設定（これ1つで全部やる）
 */
function run() {
  var sheets = SpreadsheetApp.getActiveSpreadsheet().getSheets();
  var done = [];

  for (var i = 0; i < sheets.length; i++) {
    var result = setupSheet(sheets[i]);
    if (result) done.push(result);
  }

  SpreadsheetApp.getUi().alert('完了: ' + done.join(', '));
}

// ===== トリガー =====

function onChange(e) {
  if (!e || e.changeType !== 'INSERT_SHEET') return;
  try {
    var sheets = SpreadsheetApp.getActiveSpreadsheet().getSheets();
    for (var i = 0; i < sheets.length; i++) {
      var parsed = parseSheetName(sheets[i].getName());
      if (!parsed) continue;
      if (sheets[i].getRange(3, 2).getValue() === '' || sheets[i].getRange(3, 2).getValue() === null) {
        setupSheet(sheets[i]);
        SpreadsheetApp.getActiveSpreadsheet().toast(
          parsed.year + '年' + parsed.month + '月を自動設定しました', '完了', 5);
      }
    }
  } catch (err) { Logger.log('onChange: ' + err.message); }
}

function installTrigger() {
  var triggers = ScriptApp.getProjectTriggers();
  for (var i = 0; i < triggers.length; i++) {
    if (triggers[i].getHandlerFunction() === 'onChange') ScriptApp.deleteTrigger(triggers[i]);
  }
  ScriptApp.newTrigger('onChange').forSpreadsheet(SpreadsheetApp.getActiveSpreadsheet()).onChange().create();
  SpreadsheetApp.getUi().alert('自動トリガー設定完了。新シート追加時に自動設定されます。');
}

function onOpen() {
  SpreadsheetApp.getUi()
    .createMenu('カレンダー書式')
    .addItem('一括設定（リセット＋日付＋書式）', 'run')
    .addSeparator()
    .addItem('自動トリガー設定（初回のみ）', 'installTrigger')
    .addToUi();
}
