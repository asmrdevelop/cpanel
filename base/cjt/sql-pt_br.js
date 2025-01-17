//~~GENERATED~~
//-------------------------------------------------------------
// Source:    /usr/local/cpanel/base/cjt/sql.js
// Generated: /usr/local/cpanel/base/cjt/sql-pt_br.js
// Module:    legacy_cjt/sql-pt_br
// Locale:    pt_br
// This file is generated by the cpanel localization system
// using the bin/_build_translated_js_hash_files.pl script.
//-------------------------------------------------------------
// !!! Do not hand edit this file !!!
//-------------------------------------------------------------
(function() {
    // The raw lexicon.
    var newLex = {"A database name cannot be empty.":"Um nome de banco de dados não pode ficar vazio.","A database name cannot end with a space character.":"A database name cannot end with a space character.","A username cannot be empty.":"Um nome de usuário não pode ser vazio.","Database Name":"Nome do banco de dados","Database Username":"Nome do usuário do banco de dados","The name of a database user on this system may include only the following characters: [join, ,_1]":"O nome do usuário de um banco de dados no sistema só pode incluir os seguintes caracteres: [join, ,_1]","This database name has too many wildcard-sensitive characters ([list_and_quoted,_1]). The system stores each of these as two characters internally, up to a limit of [quant,_2,character,characters]. This name would take up [quant,_3,character,characters] of internal storage, which is [numf,_4] too many.":"O nome deste banco de dados tem caracteres curinga demais ([list_and_quoted,_1]). Internamente, o sistema armazena cada um deles como dois caracteres, até o limite de [quant,_2,caractere,caracteres]. Esse nome ocuparia até [quant,_3,caractere,caracteres] de armazenamento interno, o que é [numf,_4] a mais.","This system allows only printable [asis,ASCII] characters in database names.":"Este sistema permite apenas caracteres imprimíveis [asis,ASCII] em nomes de banco de dados.","This system prohibits the backslash ([_1]) character in database names.":"This system prohibits the backslash ([_1]) character in database names.","This system prohibits the following [numerate,_1,character,characters] in database names: [join, ,_2]":"Este sistema proíbe os itens [numerate,_1, caractere, caracteres] nos nomes de bancos de dados: [join, ,_2]","This system prohibits the slash ([_1]) character in database names.":"Este sistema proíbe o caractere de barra ([_1]) em nomes de banco de dados.","This system’s database version ([_1]) prohibits the character “[_2]” in database names. Ask your administrator to upgrade to a newer version.":"This system’s database version ([_1]) prohibits the character “[_2]” in database names. Ask your administrator to upgrade to a newer version.","This value is too long by [quant,_1,character,characters]. The maximum length is [quant,_2,character,characters].":"O valor é muito longo em [quant,_1,caractere,caracteres]. O tamanho máximo é [quant,_2,caractere,caracteres].","Username cannot begin with a number.":"O nome de usuário não pode começar com um número.","[asis,PostgreSQL] Database Name":"Nome do Banco de Dados do [asis,PostgreSQL]","[asis,PostgreSQL] Username":"Nome de usuário do [asis,PostgreSQL]"};

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
