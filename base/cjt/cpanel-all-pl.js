//~~GENERATED~~
//-------------------------------------------------------------
// Source:    /usr/local/cpanel/base/cjt/cpanel-all.js
// Generated: /usr/local/cpanel/base/cjt/cpanel-all-pl.js
// Module:    legacy_cjt/cpanel-all-pl
// Locale:    pl
// This file is generated by the cpanel localization system
// using the bin/_build_translated_js_hash_files.pl script.
//-------------------------------------------------------------
// !!! Do not hand edit this file !!!
//-------------------------------------------------------------
(function() {
    // The raw lexicon.
    var newLex = {"Advanced Options":"Opcje zaawansowane","Alpha Characters":"Znaki alfanumeryczne","An unknown error occurred.":"Wystąpił nieznany błąd.","Both":"Oba","Cancel":"Anuluj","Click to close.":"Kliknij, aby zamknąć.","Close":"Zamknij","Generate Password":"Wygeneruj hasło","I have copied this password in a safe place.":"Mam skopiowane to hasło w bezpiecznym miejscu.","Length":"Długość","Loading …":"Ładowanie…","Lowercase":"Małe litery","Non Alpha Characters":"Znaki niealfanumeryczne","Numbers":"Liczby","OK":"OK","Password Generator":"Generator haseł","Password Strength":"Siła hasła","Password cannot be empty.":"Pole hasła nie może być puste.","Password strength must be at least [numf,_1].":"Siła hasła musi wynosić co najmniej [numf,_1].","Passwords Match":"Zgodność haseł","Passwords do not match.":"Hasła nie są ze sobą zgodne.","Passwords must be at least [quant,_1,character,characters] long.":"Hasła muszą zawierać co najmniej [quant,_1,znak,znaki(-ów)].","Strong":"Silne","Success!":"Powodzenie!","Symbols":"Symbole","The API response could not be parsed.":"Nie można analizować składni odpowiedzi na wywołanie interfejsu API.","Uppercase":"Wielkie litery","Use Password":"Użyj hasła","Validation Errors":"Błędy weryfikacji","Very Strong":"Bardzo silne","Very Weak":"Bardzo słabe","Weak":"Słabe","less »":"mniej »","more »":"więcej »","unlimited":"nieograniczone"};

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
//-------------------------------------------------------------
// CLDR Data for pl
//-------------------------------------------------------------
(function(context) {
    var locale = "pl",
        functions = {'get_plural_form':function(n){var category;var category_values=Array.prototype.slice.call(arguments,1);var has_extra_for_zero=0;var abs_n=Math.abs(n);var category_process_order=["zero","one","two","few","many","other"];var category_rules_lookup={"one":function(n){if(((n==1))){return'one';}return;},"few":function(n){if(((parseInt(n)==n&&(n%10)>=2&&(n%10)<=4)&&(parseInt(n)!=n||(n%100)<12||(n%100)>14))){return'few';}return;},"many":function(n){if(((n!=1)&&(parseInt(n)==n&&(n%10)>=0&&(n%10)<=1))||((parseInt(n)==n&&(n%10)>=5&&(n%10)<=9))||((parseInt(n)==n&&(n%100)>=12&&(n%100)<=14))){return'many';}return;}};for(i=0;i<category_process_order.length;i++){if(category_rules_lookup[category_process_order[i]]){category=category_rules_lookup[category_process_order[i]](abs_n);if(category)break;}}
var categories=["one","few","many","other"];if(category_values.length===0){category_values=categories;}
else{var cat_len=categories.length;var val_len=category_values.length;var cat_len_plus_one=cat_len+1;if(val_len===cat_len_plus_one){has_extra_for_zero++;}
else if(cat_len!==val_len){if(window.console)console.warn('The number of given values ('+val_len+') does not match the number of categories ('+cat_len+').');}}
if(category===undefined){var cat_idx=has_extra_for_zero&&abs_n!==0?-2:-1;var sliced=category_values.slice(cat_idx);return[sliced[0],has_extra_for_zero&&abs_n===0?1:0];}
else{var return_value;GET_POSITION:while(1){var cat_pos_in_list;var index=-1;CATEGORY:for(i=0;i<categories.length;i++){index++;if(categories[i]===category){cat_pos_in_list=index;break CATEGORY;}}
if(cat_pos_in_list===undefined&&category!=='other'){if(window.console)console.warn('The category ('+category+') is not used by this locale.');category='other';continue GET_POSITION;}
else if(cat_pos_in_list===undefined){var cat_idx=has_extra_for_zero&&abs_n!==0?-2:-1;var sliced=category_values.slice(cat_idx);return_value=[sliced[0],has_extra_for_zero&&abs_n===0?1:0]
break GET_POSITION;}
else{if(has_extra_for_zero&&category==='other'){var cat_idx=has_extra_for_zero&&abs_n===0?-1:cat_pos_in_list;var sliced=category_values.slice(cat_idx);return_value=[sliced[0],has_extra_for_zero&&abs_n===0?1:0];break GET_POSITION;}
else{return_value=[category_values[cat_pos_in_list],0];break GET_POSITION;}}
break GET_POSITION;}
return return_value;}}},
        datetime_info = {"territory":null,"quarter_stand_alone_narrow":["1","2","3","4"],"time_formats":{"short":"HH:mm","medium":"HH:mm:ss","long":"HH:mm:ss z","full":"HH:mm:ss zzzz"},"era_narrow":["p.n.e.","n.e."],"datetime_format_full":"EEEE, d MMMM y HH:mm:ss zzzz","glibc_date_1_format":"%a %b %e %H:%M:%S %Z %Y","datetime_format_long":"d MMMM y HH:mm:ss z","date_format_short":"dd-MM-yy","native_variant":null,"name":"Polish","language_id":"pl","era_wide":["p.n.e.","n.e."],"variant_id":null,"date_format_medium":"dd-MM-yyyy","time_format_default":"HH:mm:ss","era_abbreviated":["p.n.e.","n.e."],"datetime_format":"{1} {0}","month_format_wide":["stycznia","lutego","marca","kwietnia","maja","czerwca","lipca","sierpnia","września","października","listopada","grudnia"],"quarter_format_abbreviated":["K1","K2","K3","K4"],"datetime_format_short":"dd-MM-yy HH:mm","glibc_datetime_format":"%a %b %e %H:%M:%S %Y","quarter_stand_alone_abbreviated":["1 kw.","2 kw.","3 kw.","4 kw."],"script_id":null,"prefers_24_hour_time":1,"cldr_version":"1.7.1","day_format_wide":["poniedziałek","wtorek","środa","czwartek","piątek","sobota","niedziela"],"language":"Polish","month_format_narrow":["s","l","m","k","m","c","l","s","w","p","l","g"],"time_format_full":"HH:mm:ss zzzz","date_format_default":"dd-MM-yyyy","am_pm_abbreviated":["AM","PM"],"native_territory":null,"glibc_time_12_format":"%I:%M:%S %p","month_stand_alone_wide":["styczeń","luty","marzec","kwiecień","maj","czerwiec","lipiec","sierpień","wrzesień","październik","listopad","grudzień"],"time_format_long":"HH:mm:ss z","day_stand_alone_wide":["poniedziałek","wtorek","środa","czwartek","piątek","sobota","niedziela"],"variant":null,"id":"pl","available_formats":null,"quarter_stand_alone_wide":["I kwartał","II kwartał","III kwartał","IV kwartał"],"time_format_medium":"HH:mm:ss","time_format_short":"HH:mm","date_format_full":"EEEE, d MMMM y","territory_id":null,"first_day_of_week":"1","glibc_date_format":"%m/%d/%y","quarter_format_wide":["I kwartał","II kwartał","III kwartał","IV kwartał"],"day_stand_alone_abbreviated":["pon.","wt.","śr.","czw.","pt.","sob.","niedz."],"month_stand_alone_narrow":["s","l","m","k","m","c","l","s","w","p","l","g"],"format_for":{"yQQQ":"y QQQ","yMMMEd":"EEE, d MMM y","d":"d","y":"y","hms":"h:mm:ss a","MMMMd":"d MMMM","yMMMM":"LLLL y","ms":"mm:ss","M":"L","yM":"yyyy-M","MEd":"E, M-d","MMM":"LLL","Md":"d.M","yQ":"yyyy Q","yMEd":"EEE, d.M.yyyy","Hm":"H:mm","EEEd":"d EEE","Hms":"H:mm:ss","hm":"h:mm a","MMMEd":"d MMM E","MMMMEd":"d MMMM E","MMMd":"MMM d","yMMM":"y MMM"},"quarter_format_narrow":["1","2","3","4"],"date_formats":{"short":"dd-MM-yy","medium":"dd-MM-yyyy","long":"d MMMM y","full":"EEEE, d MMMM y"},"date_format_long":"d MMMM y","month_stand_alone_abbreviated":["sty","lut","mar","kwi","maj","cze","lip","sie","wrz","paź","lis","gru"],"native_language":"polski","datetime_format_default":"dd-MM-yyyy HH:mm:ss","native_name":"polski","day_format_narrow":["P","W","Ś","C","P","S","N"],"script":null,"default_time_format_length":"medium","glibc_time_format":"%H:%M:%S","native_script":null,"month_format_abbreviated":["sty","lut","mar","kwi","maj","cze","lip","sie","wrz","paź","lis","gru"],"default_date_format_length":"medium","day_stand_alone_narrow":["P","W","Ś","C","P","S","N"],"day_format_abbreviated":["pon.","wt.","śr.","czw.","pt.","sob.","niedz."],"datetime_format_medium":"dd-MM-yyyy HH:mm:ss"},
        misc_info = {"delimiters":{"quotation_start":"‘","quotation_end":"’","alternate_quotation_start":"„","alternate_quotation_end":"”"},"orientation":{"lines":"top-to-bottom","characters":"left-to-right"},"posix":{"nostr":"nie:n","yesstr":"tak:t"},"plural_forms":{"category_list":["one","few","many","other"],"category_rules_function":null,"category_rules":{"one":"n is 1","few":"n mod 10 in 2..4 and n mod 100 not in 12..14","many":"n is not 1 and n mod 10 in 0..1 or n mod 10 in 5..9 or n mod 100 in 12..14"},"category_rules_compiled":{"one":function (n) {if ( (( n == 1))) { return 'one'; } return;},"few":function (n) {if ( (( parseInt(n) == n && (n % 10) >= 2 && (n % 10) <= 4 ) && ( parseInt(n) != n || (n % 100) < 12 || (n % 100) > 14 ))) { return 'few'; } return;},"many":function (n) {if ( (( n != 1) && ( parseInt(n) == n && (n % 10) >= 0 && (n % 10) <= 1 )) ||  (( parseInt(n) == n && (n % 10) >= 5 && (n % 10) <= 9 )) ||  (( parseInt(n) == n && (n % 100) >= 12 && (n % 100) <= 14 ))) { return 'many'; } return;}}},"cldr_formats":{"territory":"Region: {0}","_decimal_format_decimal":",","language":"Język: {0}","percent":"#,##0%","locale":"{0} ({1})","_decimal_format_group":" ","_percent_format_percent":"%","decimal":"#,##0.###","ellipsis":{"medial":"{0}…{1}","final":"{0}…","initial":"…{0}"},"list_or":{"2":"{0} lub {1}","start":"{0}, {1}","end":"{0} lub {1}","middle":"{0}, {1}"},"list":{"middle":"{0}; {1}","2":"{0} i {1}","start":"{0}; {1}","end":"{0} i {1}"}},"fallback":[],"characters":{"more_information":"?"}};

    // Legacy cjt 1.0 support
    if ( context.YAHOO ) {
        context.YAHOO.util.Event.onDOMReady(function() {
            var Locale = CPANEL.Locale.generateClassFromCldr(locale, functions, datetime_info, misc_info);
            context.LOCALE = new Locale();
        });
    }

    // Modern cjt 2.0 support
    context.CJT2_loader = {
        current_locale: locale,
        CLDR: {}
    };

    var CLDR = {
        locale: locale,
        functions: functions,
        datetime_info: datetime_info,
        misc_info: misc_info
    };

    context.CJT2_loader.CLDR[locale] = CLDR;
    context.CLDR = CLDR;

})(window);
//~~END-GENERATED~~
