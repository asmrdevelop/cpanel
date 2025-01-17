//~~GENERATED~~
//-------------------------------------------------------------
// Source:    /usr/local/cpanel/base/cjt/cpanel-all.js
// Generated: /usr/local/cpanel/base/cjt/cpanel-all-el.js
// Module:    legacy_cjt/cpanel-all-el
// Locale:    el
// This file is generated by the cpanel localization system
// using the bin/_build_translated_js_hash_files.pl script.
//-------------------------------------------------------------
// !!! Do not hand edit this file !!!
//-------------------------------------------------------------
(function() {
    // The raw lexicon.
    var newLex = {"Advanced Options":"Σύνθετες επιλογές","Alpha Characters":"Χαρακτήρες Alpha","An unknown error occurred.":"Παρουσιάστηκε άγνωστο σφάλμα.","Both":"Και τα δύο","Cancel":"Άκυρο","Click to close.":"Κάντε κλικ για κλείσιμο.","Close":"Κλείσιμο","Generate Password":"Δημιουργία κωδικού πρόσβασης","I have copied this password in a safe place.":"Έχω αντιγράψει αυτόν τον κωδικό πρόσβασης σε ασφαλές σημείο.","Length":"Μήκος","Loading …":"Φόρτωση…","Lowercase":"Πεζά γράμματα","Non Alpha Characters":"Χαρακτήρες που δεν είναι Alpha","Numbers":"Αριθμοί","OK":"OK","Password Generator":"Δημιουργία κωδικών πρόσβασης","Password Strength":"Ισχύς κωδικού πρόσβασης","Password cannot be empty.":"Ο κωδικός πρόσβασης δεν πρέπει να είναι κενός.","Password strength must be at least [numf,_1].":"Η ισχύς του κωδικού πρόσβασης πρέπει να είναι τουλάχιστον [numf,_1].","Passwords Match":"Οι κωδικοί πρόσβασης ταιριάζουν","Passwords do not match.":"Οι κωδικοί πρόσβασης δεν ταιριάζουν.","Passwords must be at least [quant,_1,character,characters] long.":"Οι φράσεις πρόσβασης πρέπει να έχουν τουλάχιστον [quant,_1,χαρακτήρα,χαρακτήρες].","Strong":"Ισχυρός","Success!":"Επιτυχία!","Symbols":"Σύμβολα","The API response could not be parsed.":"Δεν ήταν δυνατή η ανάλυση της απάντησης του API.","Uppercase":"Κεφαλαία γράμματα","Use Password":"Χρήση κωδικού πρόσβασης","Validation Errors":"Σφάλματα επικύρωσης","Very Strong":"Πολύ ισχυρός","Very Weak":"Πολύ αδύναμος","Weak":"Αδύναμος","less »":"λιγότερα »","more »":"περισσότερα »","unlimited":"απεριόριστα"};

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
// CLDR Data for el
//-------------------------------------------------------------
(function(context) {
    var locale = "el",
        functions = {'get_plural_form':function(n){var category;var category_values=Array.prototype.slice.call(arguments,1);var has_extra_for_zero=0;var abs_n=Math.abs(n);var category_process_order=["zero","one","two","few","many","other"];var category_rules_lookup={"one":function(n){if(((n==1))){return'one';}return;}};for(i=0;i<category_process_order.length;i++){if(category_rules_lookup[category_process_order[i]]){category=category_rules_lookup[category_process_order[i]](abs_n);if(category)break;}}
var categories=["one","other"];if(category_values.length===0){category_values=categories;}
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
        datetime_info = {"territory":null,"quarter_stand_alone_narrow":["1","2","3","4"],"time_formats":{"short":"h:mm a","medium":"h:mm:ss a","long":"h:mm:ss a z","full":"h:mm:ss a zzzz"},"era_narrow":["π.Χ.","μ.Χ."],"datetime_format_full":"EEEE, dd MMMM y h:mm:ss a zzzz","glibc_date_1_format":"%a %b %e %H:%M:%S %Z %Y","datetime_format_long":"dd MMMM y h:mm:ss a z","date_format_short":"dd/MM/yyyy","native_variant":null,"name":"Greek","language_id":"el","era_wide":["π.Χ.","μ.Χ."],"variant_id":null,"date_format_medium":"dd MMM y","time_format_default":"h:mm:ss a","era_abbreviated":["π.Χ.","μ.Χ."],"datetime_format":"{1} {0}","month_format_wide":["Ιανουαρίου","Φεβρουαρίου","Μαρτίου","Απριλίου","Μαΐου","Ιουνίου","Ιουλίου","Αυγούστου","Σεπτεμβρίου","Οκτωβρίου","Νοεμβρίου","Δεκεμβρίου"],"quarter_format_abbreviated":["Τ1","Τ2","Τ3","Τ4"],"datetime_format_short":"dd/MM/yyyy h:mm a","glibc_datetime_format":"%a %b %e %H:%M:%S %Y","quarter_stand_alone_abbreviated":["Τ1","Τ2","Τ3","Τ4"],"script_id":null,"prefers_24_hour_time":0,"cldr_version":"1.7.1","day_format_wide":["Δευτέρα","Τρίτη","Τετάρτη","Πέμπτη","Παρασκευή","Σάββατο","Κυριακή"],"language":"Greek","month_format_narrow":["Ι","Φ","Μ","Α","Μ","Ι","Ι","Α","Σ","Ο","Ν","Δ"],"time_format_full":"h:mm:ss a zzzz","date_format_default":"dd MMM y","am_pm_abbreviated":["π.μ.","μ.μ."],"native_territory":null,"glibc_time_12_format":"%I:%M:%S %p","month_stand_alone_wide":["Ιανουάριος","Φεβρουάριος","Μάρτιος","Απρίλιος","Μάιος","Ιούνιος","Ιούλιος","Αύγουστος","Σεπτέμβριος","Οκτώβριος","Νοέμβριος","Δεκέμβριος"],"time_format_long":"h:mm:ss a z","day_stand_alone_wide":["Δευτέρα","Τρίτη","Τετάρτη","Πέμπτη","Παρασκευή","Σάββατο","Κυριακή"],"variant":null,"id":"el","available_formats":null,"quarter_stand_alone_wide":["1ο τρίμηνο","2ο τρίμηνο","3ο τρίμηνο","4ο τρίμηνο"],"time_format_medium":"h:mm:ss a","time_format_short":"h:mm a","date_format_full":"EEEE, dd MMMM y","territory_id":null,"first_day_of_week":"1","glibc_date_format":"%m/%d/%y","quarter_format_wide":["1ο τρίμηνο","2ο τρίμηνο","3ο τρίμηνο","4ο τρίμηνο"],"day_stand_alone_abbreviated":["Δευ","Τρι","Τετ","Πεμ","Παρ","Σαβ","Κυρ"],"month_stand_alone_narrow":["Ι","Φ","Μ","Α","Μ","Ι","Ι","Α","Σ","Ο","Ν","Δ"],"format_for":{"yQQQ":"y QQQ","yMMMEd":"EEE, d MMM y","d":"d","y":"y","hms":"h:mm:ss a","MMMMd":"d MMMM","yMMMM":"LLLL y","ms":"mm:ss","M":"L","yM":"M/yyyy","MEd":"E, d/M","MMM":"LLL","Md":"d/M","yQ":"y Q","yMEd":"EEE, d/M/yyyy","Hm":"H:mm","EEEd":"EEE d","Hms":"H:mm:ss","hm":"h:mm a","MMMEd":"E, d MMM","MMMMEd":"E, d MMMM","MMMd":"d MMM","yMMM":"MMM y"},"quarter_format_narrow":["1","2","3","4"],"date_formats":{"short":"dd/MM/yyyy","medium":"dd MMM y","long":"dd MMMM y","full":"EEEE, dd MMMM y"},"date_format_long":"dd MMMM y","month_stand_alone_abbreviated":["Ιαν","Φεβ","Μαρ","Απρ","Μαϊ","Ιουν","Ιουλ","Αυγ","Σεπ","Οκτ","Νοε","Δεκ"],"native_language":"Ελληνικά","datetime_format_default":"dd MMM y h:mm:ss a","native_name":"Ελληνικά","day_format_narrow":["Δ","Τ","Τ","Π","Π","Σ","Κ"],"script":null,"default_time_format_length":"medium","glibc_time_format":"%H:%M:%S","native_script":null,"month_format_abbreviated":["Ιαν","Φεβ","Μαρ","Απρ","Μαϊ","Ιουν","Ιουλ","Αυγ","Σεπ","Οκτ","Νοε","Δεκ"],"default_date_format_length":"medium","day_stand_alone_narrow":["Δ","Τ","Τ","Π","Π","Σ","Κ"],"day_format_abbreviated":["Δευ","Τρι","Τετ","Πεμ","Παρ","Σαβ","Κυρ"],"datetime_format_medium":"dd MMM y h:mm:ss a"},
        misc_info = {"delimiters":{"quotation_start":"«","quotation_end":"»","alternate_quotation_start":"‘","alternate_quotation_end":"’"},"orientation":{"lines":"top-to-bottom","characters":"left-to-right"},"posix":{"nostr":"όχι:ό","yesstr":"ναι:ν"},"plural_forms":{"category_list":["one","other"],"category_rules_function":null,"category_rules":{"one":"n is 1"},"category_rules_compiled":{"one":function (n) {if ( (( n == 1))) { return 'one'; } return;}}},"cldr_formats":{"territory":"Περιοχή: {0}","_decimal_format_decimal":",","language":"Γλώσσα: {0}","percent":"#,##0%","locale":"{0} ({1})","_decimal_format_group":".","_percent_format_percent":"%","decimal":"#,##0.###","ellipsis":{"medial":"{0}…{1}","final":"{0}…","initial":"…{0}"},"list_or":{"start":"{0}, {1}","end":"{0} ή {1}","middle":"{0}, {1}","2":"{0} ή {1}"},"list":{"middle":"{0}, {1}","2":"{0} και {1}","start":"{0}, {1}","end":"{0} και {1}"}},"fallback":[],"characters":{"more_information":";"}};

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
