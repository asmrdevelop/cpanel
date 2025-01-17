//~~GENERATED~~
//-------------------------------------------------------------
// Source:    /usr/local/cpanel/base/sharedjs/transfers/TransferSession.js
// Generated: /usr/local/cpanel/base/sharedjs/transfers/TransferSession-pl.js
// Module:    legacy_shared/transfers/TransferSession-pl
// Locale:    pl
// This file is generated by the cpanel localization system
// using the bin/_build_translated_js_hash_files.pl script.
//-------------------------------------------------------------
// !!! Do not hand edit this file !!!
//-------------------------------------------------------------
(function() {
    // The raw lexicon.
    var newLex = {"Abort Session Processing":"Przerwij przetwarzanie sesji","Are you sure you want to abort this transfer?":"Czy na pewno chcesz przerwać ten transfer?","Are you sure you want to pause this transfer?":"Czy na pewno chcesz wstrzymać ten transfer?","Failed to abort the session.":"Nie można przerwać sesji.","Failed to pause the session.":"Nie można wstrzymać sesji.","Failed to start transfer.":"Nie można rozpocząć transferu.","Pausing queue processing …":"Trwa wstrzymywanie przetwarzania kolejki…","The system will abort any transfer processes as soon as possible. In order to prevent data loss, the system will complete ongoing restore operations before the entire session aborts.":"System przerwie wszelkie procesy transferu najszybciej, jak będzie to możliwe. Aby zapobiec utracie danych, system dokończy operacje przywracania będące w toku, zanim cała sesja zostanie przerwana.","The system will not add new items to the queue until you choose to resume. In order to prevent data loss, the system will complete ongoing operations.":"System nie doda nowych elementów do kolejki, dopóki nie wybierzesz opcji wznowienia działania. Aby zapobiec utracie danych, system dokończy operacje będące w toku.","There is no handler for [asis,sessionState]: [_1]":"Brak programu obsługi w przypadku elementu [asis,sessionState]: [_1]"};

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
