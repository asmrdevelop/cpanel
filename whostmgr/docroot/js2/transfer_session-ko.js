//~~GENERATED~~
//-------------------------------------------------------------
// Source:    /usr/local/cpanel/whostmgr/docroot/js2/transfer_session.js
// Generated: /usr/local/cpanel/whostmgr/docroot/js2/transfer_session-ko.js
// Module:    /js2/transfer_session-ko
// Locale:    ko
// This file is generated by the cpanel localization system
// using the bin/_build_translated_js_hash_files.pl script.
//-------------------------------------------------------------
// !!! Do not hand edit this file !!!
//-------------------------------------------------------------
(function() {
    // The raw lexicon.
    var newLex = {"Abort":"중단","Abort Session Processing":"세션 처리 중단","Aborting …":"중단하는 중…","Alert":"경고","Confirm":"확인","Loading …":"로드하는 중 …","OK":"확인","Pause":"일시 중지","Pausing queue processing …":"대기열 처리 일시 중지 중…","Pausing …":"일시 중지 중…","Resume":"다시 시작","The system will abort any transfer processes as soon as possible. In order to prevent data loss, the system will complete ongoing restore operations before the entire session aborts.":"어떤 전송 프로세스든 최대한 빨리 중단됩니다. 데이터 손실을 예방하기 위해, 시스템에서 진행 중인 복원 작업을 완료한 후 전체 세션이 중단됩니다.","The system will not add new items to the queue until you choose to resume. In order to prevent data loss, the system will complete ongoing operations.":"다시 시작하기로 선택할 때까지는 대기열에 새 항목이 추가되지 않습니다. 데이터 손실을 예방하기 위해, 시스템에서 진행 중인 작업을 완료합니다."};

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
