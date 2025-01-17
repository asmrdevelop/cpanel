//~~GENERATED~~
//-------------------------------------------------------------
// Source:    /usr/local/cpanel/base/sharedjs/transfers/TransferSession.js
// Generated: /usr/local/cpanel/base/sharedjs/transfers/TransferSession-es_es.js
// Module:    legacy_shared/transfers/TransferSession-es_es
// Locale:    es_es
// This file is generated by the cpanel localization system
// using the bin/_build_translated_js_hash_files.pl script.
//-------------------------------------------------------------
// !!! Do not hand edit this file !!!
//-------------------------------------------------------------
(function() {
    // The raw lexicon.
    var newLex = {"Abort Session Processing":"Abortar procesamiento de la sesión","Are you sure you want to abort this transfer?":"¿Está seguro de que desea abortar esta transferencia?","Are you sure you want to pause this transfer?":"¿Está seguro de que desea pausar esta transferencia?","Failed to abort the session.":"No se pudo abortar la sesión.","Failed to pause the session.":"Error al pausar la sesión.","Failed to start transfer.":"Error al iniciar la transferencia.","Pausing queue processing …":"Pausando el procesamiento de la cola …","The system will abort any transfer processes as soon as possible. In order to prevent data loss, the system will complete ongoing restore operations before the entire session aborts.":"El sistema abortará cualquier proceso de transferencia lo antes posible. Para evitar posibles pérdidas de datos, el sistema completará las operaciones de restauración en curso ante de que se aborte toda la sesión.","The system will not add new items to the queue until you choose to resume. In order to prevent data loss, the system will complete ongoing operations.":"El sistema no añadirá nuevos elementos a la cola hasta que escoja reanudar. Con el fin de evitar posibles pérdidas de datos, el sistema completará las operaciones en curso.","There is no handler for [asis,sessionState]: [_1]":"There is no handler for [asis,sessionState]: [_1]"};

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
