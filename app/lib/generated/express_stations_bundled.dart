// GENERATED FILE - DO NOT EDIT.
// 由 tool/gen_express_stations.dart 从 data/express_stations.json 生成。
// CI 每次编译前会重新生成，保证出厂包里带的是最新快递站数据。
library;

/// 编译期内置的快递站数据快照（出厂初始值，可被热更新覆盖）。
const String kBundledExpressStationJson = r'''
{
  "schemaVersion": 1,
  "revision": 1,
  "updatedAt": "2026-11-12",
  "description": "掌上砚园「快递站状态」页的唯一数据源。位置、备注留空表示待补充；改完推送到 main 后，同步脚本会自动推到 Gitee 仓库同路径，App 进页即可热更新；CI 编译时会把本文件合入安装包作为出厂初始数据。每次改动请把 revision 加 1 并更新 updatedAt。",
  "notice": "此模块时间仅作功能演示，部分内容待修正，部分数据待补充。",
  "groups": [
    {
      "id": "campus",
      "name": "校内",
      "location": "肇庆学院主校区校内",
      "note": "",
      "stations": [
        {
          "id": "campus-jd",
          "name": "京东快递站",
          "location": "",
          "hours": "10:00-19:00",
          "note": ""
        },
        {
          "id": "campus-sf",
          "name": "顺丰营业点",
          "location": "",
          "hours": "10:00-19:00",
          "note": ""
        }
      ]
    },
    {
      "id": "east-gate",
      "name": "东门",
      "location": "主校区东门",
      "note": "校门 23:00 关闭，关门后驿站即使营业也无法进出。",
      "gateHours": "07:00-23:00",
      "stations": [
        {
          "id": "east-cainiao",
          "name": "东门菜鸟驿站",
          "location": "",
          "hours": "10:00-23:00",
          "note": ""
        },
        {
          "id": "east-shentong",
          "name": "东门申通快递",
          "location": "",
          "hours": "10:00-21:00",
          "note": ""
        },
        {
          "id": "east-kfc",
          "name": "肯德基旁驿站",
          "location": "",
          "hours": "10:00-21:00",
          "weekdayHours": {
            "5": "11:00-20:50"
          },
          "note": "周五营业时间与其他日不同。"
        },
        {
          "id": "east-cainiao-tea",
          "name": "菜鸟の茶驿站",
          "location": "",
          "hours": "10:00-22:00",
          "note": ""
        }
      ]
    },
    {
      "id": "south-gate",
      "name": "南门",
      "location": "主校区南门",
      "note": "",
      "stations": [
        {
          "id": "south-garage",
          "name": "南门车库驿站",
          "location": "",
          "note": "营业时间与具体位置待补充，欢迎反馈。"
        }
      ]
    },
    {
      "id": "north-gate",
      "name": "北门",
      "location": "主校区北门",
      "note": "",
      "stations": [
        {
          "id": "north-station",
          "name": "北门驿站",
          "location": "",
          "note": "营业时间与具体位置待补充，欢迎反馈。"
        }
      ]
    }
  ]
}
''';
