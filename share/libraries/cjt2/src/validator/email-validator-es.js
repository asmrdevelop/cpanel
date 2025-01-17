//~~GENERATED~~
//-------------------------------------------------------------
// Source:    /usr/local/cpanel/share/libraries/cjt2/src/validator/email-validator.js
// Generated: /usr/local/cpanel/share/libraries/cjt2/src/validator/email-validator-es.js
// Module:    cjt/validator/email-validator-es
// Locale:    es
// This file is generated by the cpanel localization system
// using the bin/_build_translated_js_hash_files.pl script.
//-------------------------------------------------------------
// !!! Do not hand edit this file !!!
//-------------------------------------------------------------
(function() {
    // The raw lexicon.
    var newLex = {"Do not include the [asis,@] character or the domain name.":"No incluya el carácter [asis,@] o el nombre de dominio.","The email must contain a username and a domain.":"El correo electrónico debe tener un nombre de usuario y un dominio.","The username can only contain letters, numbers, periods, hyphens, and underscores.":"El nombre de usuario solo puede contener letras, números, puntos, guiones y guiones bajos.","The username can only contain the following characters: [asis,a-zA-Z0-9!#$%][output,asis,amp()][output,apos][asis,*+/=?^_`{|}~-]":"El nombre de usuario solo puede contener los caracteres siguientes: [asis,a-zA-Z0-9!#$%][output,asis,amp()][output,apos][asis,*+/=?^_`{|}~-]","The username cannot begin or end with a period.":"El nombre de usuario no puede comenzar ni terminar con un punto.","The username cannot contain two consecutive periods.":"El nombre de usuario no puede tener dos puntos consecutivos.","The username cannot exceed [numf,_1] characters.":"El nombre de usuario no puede exceder los [numf,_1] caracteres.","You must enter a username.":"Debe ingresar un nombre de usuario."};

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
