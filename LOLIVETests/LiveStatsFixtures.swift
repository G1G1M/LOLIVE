//
//  LiveStatsFixtures.swift
//  LOLIVETests
//
//  Riot 라이브 스탯 피드(feed.lolesports.com)의 **실제 응답**을 그대로 박아둔 픽스처.
//  2026-08-27 LCK BFX vs NS 1세트(gameId 117030752644841578) 30분 시점에서 캡처했고,
//  프레임 수만 줄였을 뿐 필드는 손대지 않았다.
//
//  [왜 실측을 박아두나] Riot이 공식 문서 없는 비공식 API를 예고 없이 바꾼다.
//  실제로 details 응답에서 events/gameTime 필드가 사라져 킬 타임라인과 인게임 시계가
//  조용히 죽어 있었는데, 아무 테스트도 실패하지 않아서 한동안 아무도 몰랐다.
//  여기 픽스처를 기준으로 파싱을 고정해두면 다음 변경은 테스트가 먼저 잡는다.
//

import Foundation

enum LiveStatsFixtures {

    /// `/livestats/v1/window/{gameId}?startingTime=...` 응답 (프레임 1개로 축약)
    static let windowJSON = #"""
{"esportsGameId":"117030752644841578","esportsMatchId":"117030752644841577","gameMetadata":{"patchVersion":"16.16.809.3269","blueTeamMetadata":{"esportsTeamId":"100725845022060229","participantMetadata":[{"participantId":1,"esportsPlayerId":"105501790021137688","summonerName":"BFX Clear","championId":"Jayce","role":"top"},{"participantId":2,"esportsPlayerId":"107492130895812257","summonerName":"BFX Raptor","championId":"LeeSin","role":"jungle"},{"participantId":3,"esportsPlayerId":"105501715923396261","summonerName":"BFX VicLa","championId":"Galio","role":"mid"},{"participantId":4,"esportsPlayerId":"105501797931408936","summonerName":"BFX Taeyoon","championId":"Caitlyn","role":"bottom"},{"participantId":5,"esportsPlayerId":"101388913291808185","summonerName":"BFX Kellin","championId":"Bard","role":"support"}]},"redTeamMetadata":{"esportsTeamId":"102747101565183056","participantMetadata":[{"participantId":6,"esportsPlayerId":"100428088879195423","summonerName":"NS Kingen","championId":"Camille","role":"top"},{"participantId":7,"esportsPlayerId":"108366332471078988","summonerName":"NS Sponge","championId":"JarvanIV","role":"jungle"},{"participantId":8,"esportsPlayerId":"98767975951139628","summonerName":"NS Scout","championId":"Orianna","role":"mid"},{"participantId":9,"esportsPlayerId":"109523135356383683","summonerName":"NS Diable","championId":"Jhin","role":"bottom"},{"participantId":10,"esportsPlayerId":"99871276332909841","summonerName":"NS Lehends","championId":"Shen","role":"support"}]}},"frames":[{"rfc460Timestamp":"2026-08-27T08:30:09.879Z","gameState":"in_game","blueTeam":{"totalGold":40523,"inhibitors":0,"towers":2,"barons":0,"totalKills":6,"dragons":["hextech"],"participants":[{"participantId":1,"totalGold":9735,"level":15,"kills":2,"deaths":3,"assists":3,"creepScore":226,"currentHealth":2695,"maxHealth":2695},{"participantId":2,"totalGold":8332,"level":13,"kills":1,"deaths":4,"assists":3,"creepScore":167,"currentHealth":1563,"maxHealth":2542},{"participantId":3,"totalGold":7554,"level":13,"kills":2,"deaths":5,"assists":0,"creepScore":183,"currentHealth":2139,"maxHealth":2534},{"participantId":4,"totalGold":9689,"level":13,"kills":1,"deaths":2,"assists":0,"creepScore":233,"currentHealth":1816,"maxHealth":1816},{"participantId":5,"totalGold":5213,"level":8,"kills":0,"deaths":2,"assists":3,"creepScore":13,"currentHealth":1739,"maxHealth":1739}]},"redTeam":{"totalGold":48664,"inhibitors":0,"towers":5,"barons":0,"totalKills":16,"dragons":["infernal","cloud","cloud"],"participants":[{"participantId":6,"totalGold":10034,"level":15,"kills":7,"deaths":1,"assists":3,"creepScore":204,"currentHealth":2559,"maxHealth":2822},{"participantId":7,"totalGold":9848,"level":14,"kills":2,"deaths":1,"assists":12,"creepScore":176,"currentHealth":2723,"maxHealth":2812},{"participantId":8,"totalGold":10844,"level":15,"kills":3,"deaths":1,"assists":9,"creepScore":238,"currentHealth":2126,"maxHealth":2229},{"participantId":9,"totalGold":11159,"level":14,"kills":1,"deaths":0,"assists":10,"creepScore":241,"currentHealth":2248,"maxHealth":2248},{"participantId":10,"totalGold":6779,"level":9,"kills":3,"deaths":3,"assists":7,"creepScore":38,"currentHealth":2042,"maxHealth":2042}]}}]}
"""#

    /// `/livestats/v1/details/{gameId}?startingTime=...` 응답 (프레임 1개·선수 2명으로 축약)
    static let detailsJSON = #"""
{"frames":[{"rfc460Timestamp":"2026-08-27T08:30:09.879Z","participants":[{"participantId":1,"level":15,"kills":2,"deaths":3,"assists":3,"totalGoldEarned":9735,"creepScore":226,"killParticipation":0.8333333333333334,"championDamageShare":0.2835886953576407,"wardsPlaced":7,"wardsDestroyed":4,"attackDamage":300,"abilityPower":0,"criticalChance":0.0,"attackSpeed":144,"lifeSteal":0,"armor":113,"magicResistance":47,"tenacity":0.0,"items":[1055,3047,3161,3134,3364,1037],"perkMetadata":{"styleId":8400,"subStyleId":8300,"perks":[8437,8446,8473,8242,8313,8347,5008,5011]},"abilities":["R","Q","E","W","Q","Q","W","Q","W","Q","W","W","Q","W","E","E","E"]},{"participantId":2,"level":13,"kills":1,"deaths":4,"assists":3,"totalGoldEarned":8332,"creepScore":167,"killParticipation":0.6666666666666666,"championDamageShare":0.19836944713833263,"wardsPlaced":17,"wardsDestroyed":1,"attackDamage":223,"abilityPower":0,"criticalChance":0.0,"attackSpeed":165,"lifeSteal":0,"armor":85,"magicResistance":54,"tenacity":0.0,"items":[6692,6610,3067,1036,2055],"perkMetadata":{"styleId":8000,"subStyleId":8300,"perks":[8010,9111,9104,8299,8304,8347,5005,5008,5011]},"abilities":["Q","E","W","Q","Q","R","Q","W","Q","E","R","E","E"]}]}]}
"""#

    static var windowData: Data { Data(windowJSON.utf8) }
    static var detailsData: Data { Data(detailsJSON.utf8) }
}
