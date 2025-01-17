//~~GENERATED~~
//-------------------------------------------------------------
// Source:    /usr/local/cpanel/base/sharedjs/transfers/TransferSession.js
// Generated: /usr/local/cpanel/base/sharedjs/transfers/TransferSession-id.js
// Module:    legacy_shared/transfers/TransferSession-id
// Locale:    id
// This file is generated by the cpanel localization system
// using the bin/_build_translated_js_hash_files.pl script.
//-------------------------------------------------------------
// !!! Do not hand edit this file !!!
//-------------------------------------------------------------
(function() {
    // The raw lexicon.
    var newLex = {"Abort Session Processing":"Batalkan Pemrosesan Sesi","Are you sure you want to abort this transfer?":"Yakin ingin membatalkan transfer ini?","Are you sure you want to pause this transfer?":"Yakin ingin menjeda transfer ini?","Failed to abort the session.":"Gagal menghentikan sesi.","Failed to pause the session.":"Gagal menjeda sesi.","Failed to start transfer.":"Gagal memulai transfer.","Pausing queue processing …":"Menjeda pemrosesan antrean …","The system will abort any transfer processes as soon as possible. In order to prevent data loss, the system will complete ongoing restore operations before the entire session aborts.":"Sistem akan sesegera mungkin membatalkan proses transfer apa pun. Untuk menghindari hilangnya data, sistem akan menyelesaikan operasi pemulihan berkelanjutan sebelum membatalkan seluruh sesi.","The system will not add new items to the queue until you choose to resume. In order to prevent data loss, the system will complete ongoing operations.":"Sistem tidak akan menambahkan item baru ke antrean hingga Anda memilih untuk melanjutkan. Untuk mencegah kehilangan data, sistem akan menyelesaikan operasi yang berjalan.","There is no handler for [asis,sessionState]: [_1]":"Tidak ada penangan untuk [asis,sessionState]: [_1]"};

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
