//~~GENERATED~~
//-------------------------------------------------------------
// Source:    /usr/local/cpanel/base/sharedjs/transfers/TransferSession.js
// Generated: /usr/local/cpanel/base/sharedjs/transfers/TransferSession-zh.js
// Module:    legacy_shared/transfers/TransferSession-zh
// Locale:    zh
// This file is generated by the cpanel localization system
// using the bin/_build_translated_js_hash_files.pl script.
//-------------------------------------------------------------
// !!! Do not hand edit this file !!!
//-------------------------------------------------------------
(function() {
    // The raw lexicon.
    var newLex = {"Abort Session Processing":"中止会话处理","Are you sure you want to abort this transfer?":"是否确定要中止此传输?","Are you sure you want to pause this transfer?":"是否确定要暂停此传输?","Failed to abort the session.":"无法中止会话。","Failed to pause the session.":"无法暂停会话。","Failed to start transfer.":"无法启动传输。","Pausing queue processing …":"正在暂停队列处理…","The system will abort any transfer processes as soon as possible. In order to prevent data loss, the system will complete ongoing restore operations before the entire session aborts.":"系统将尽快中止所有传输进程。 为避免数据丢失，系统将在整个会话中止之前完成正在进行的还原操作。","The system will not add new items to the queue until you choose to resume. In order to prevent data loss, the system will complete ongoing operations.":"在您选择恢复之前，系统不会向队列添加新项目。 为避免数据丢失，系统将完成正在进行的操作。","There is no handler for [asis,sessionState]: [_1]":"没有 [asis,sessionState] 的处理程序: [_1]"};

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
