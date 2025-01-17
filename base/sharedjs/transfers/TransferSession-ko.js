//~~GENERATED~~
//-------------------------------------------------------------
// Source:    /usr/local/cpanel/base/sharedjs/transfers/TransferSession.js
// Generated: /usr/local/cpanel/base/sharedjs/transfers/TransferSession-ko.js
// Module:    legacy_shared/transfers/TransferSession-ko
// Locale:    ko
// This file is generated by the cpanel localization system
// using the bin/_build_translated_js_hash_files.pl script.
//-------------------------------------------------------------
// !!! Do not hand edit this file !!!
//-------------------------------------------------------------
(function() {
    // The raw lexicon.
    var newLex = {"Abort Session Processing":"세션 처리 중단","Are you sure you want to abort this transfer?":"이 전송을 중단하시겠습니까?","Are you sure you want to pause this transfer?":"이 전송을 일시 중지하시겠습니까?","Failed to abort the session.":"세션을 중단하지 못했습니다.","Failed to pause the session.":"세션을 일시 중지하지 못했습니다.","Failed to start transfer.":"전송을 시작하지 못했습니다.","Pausing queue processing …":"대기열 처리 일시 중지 중…","The system will abort any transfer processes as soon as possible. In order to prevent data loss, the system will complete ongoing restore operations before the entire session aborts.":"어떤 전송 프로세스든 최대한 빨리 중단됩니다. 데이터 손실을 예방하기 위해, 시스템에서 진행 중인 복원 작업을 완료한 후 전체 세션이 중단됩니다.","The system will not add new items to the queue until you choose to resume. In order to prevent data loss, the system will complete ongoing operations.":"다시 시작하기로 선택할 때까지는 대기열에 새 항목이 추가되지 않습니다. 데이터 손실을 예방하기 위해, 시스템에서 진행 중인 작업을 완료합니다.","There is no handler for [asis,sessionState]: [_1]":"[asis,sessionState]의 처리기가 없습니다. [_1]"};

    if (!this.LEXICON) {
        this.LEXICON = {};
    }

    for(var item in newLex) {
        if(newLex.hasOwnProperty(item)) {
            var value = newLex[item];
            if (typeof(value) === "string" && value !== "") {
                // Only add it if there is a value.
                this.LEXICON[item] = value;
            }
        }
    }
})();
//~~END-GENERATED~~
