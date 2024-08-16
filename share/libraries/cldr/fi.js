//-------------------------------------------------------------
// CLDR Data for fi
//-------------------------------------------------------------
(function(context) {
    var locale = "fi",
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
        datetime_info = {"territory":null,"quarter_stand_alone_narrow":["1","2","3","4"],"time_formats":{"short":"H.mm","medium":"H.mm.ss","long":"H.mm.ss z","full":"H.mm.ss zzzz"},"era_narrow":["eKr.","jKr."],"datetime_format_full":"EEEE d. MMMM y H.mm.ss zzzz","glibc_date_1_format":"%a %b %e %H:%M:%S %Z %Y","datetime_format_long":"d. MMMM y H.mm.ss z","date_format_short":"d.M.yyyy","native_variant":null,"name":"Finnish","language_id":"fi","era_wide":["ennen Kristuksen syntymää","jälkeen Kristuksen syntymän"],"variant_id":null,"date_format_medium":"d.M.yyyy","time_format_default":"H.mm.ss","era_abbreviated":["eKr.","jKr."],"datetime_format":"{1} {0}","month_format_wide":["tammikuuta","helmikuuta","maaliskuuta","huhtikuuta","toukokuuta","kesäkuuta","heinäkuuta","elokuuta","syyskuuta","lokakuuta","marraskuuta","joulukuuta"],"quarter_format_abbreviated":["1. nelj.","2. nelj.","3. nelj.","4. nelj."],"datetime_format_short":"d.M.yyyy H.mm","glibc_datetime_format":"%a %b %e %H:%M:%S %Y","quarter_stand_alone_abbreviated":["1. nelj.","2. nelj.","3. nelj.","4. nelj."],"script_id":null,"prefers_24_hour_time":1,"cldr_version":"1.7.1","day_format_wide":["maanantaina","tiistaina","keskiviikkona","torstaina","perjantaina","lauantaina","sunnuntaina"],"language":"Finnish","month_format_narrow":["T","H","M","H","T","K","H","E","S","L","M","J"],"time_format_full":"H.mm.ss zzzz","date_format_default":"d.M.yyyy","am_pm_abbreviated":["ap.","ip."],"native_territory":null,"glibc_time_12_format":"%I:%M:%S %p","month_stand_alone_wide":["tammikuu","helmikuu","maaliskuu","huhtikuu","toukokuu","kesäkuu","heinäkuu","elokuu","syyskuu","lokakuu","marraskuu","joulukuu"],"time_format_long":"H.mm.ss z","day_stand_alone_wide":["maanantai","tiistai","keskiviikko","torstai","perjantai","lauantai","sunnuntai"],"variant":null,"id":"fi","available_formats":null,"quarter_stand_alone_wide":["1. neljännes","2. neljännes","3. neljännes","4. neljännes"],"time_format_medium":"H.mm.ss","time_format_short":"H.mm","date_format_full":"EEEE d. MMMM y","territory_id":null,"first_day_of_week":"1","glibc_date_format":"%m/%d/%y","quarter_format_wide":["1. neljännes","2. neljännes","3. neljännes","4. neljännes"],"day_stand_alone_abbreviated":["ma","ti","ke","to","pe","la","su"],"month_stand_alone_narrow":["T","H","M","H","T","K","H","E","S","L","M","J"],"format_for":{"yQQQ":"QQQ y","yMMMEd":"EEE d. MMM y","d":"d","y":"y","hms":"h.mm.ss a","MMMMd":"d. MMMM","yMMMM":"LLLL y","ms":"mm.ss","M":"L","yM":"L.yyyy","MEd":"E d.M.","MMM":"LLL","Md":"d.M.","yQ":"Q/yyyy","yMEd":"EEE d.M.yyyy","Hm":"H.mm","EEEd":"EEE d.","Hms":"H:mm:ss","hm":"h.mm a","MMMEd":"E d. MMM","MMMMEd":"E d. MMMM","MMMd":"d. MMM","yMMM":"LLL y"},"quarter_format_narrow":["1","2","3","4"],"date_formats":{"short":"d.M.yyyy","medium":"d.M.yyyy","long":"d. MMMM y","full":"EEEE d. MMMM y"},"date_format_long":"d. MMMM y","month_stand_alone_abbreviated":["tammi","helmi","maalis","huhti","touko","kesä","heinä","elo","syys","loka","marras","joulu"],"native_language":"suomi","datetime_format_default":"d.M.yyyy H.mm.ss","native_name":"suomi","day_format_narrow":["M","T","K","T","P","L","S"],"script":null,"default_time_format_length":"medium","glibc_time_format":"%H:%M:%S","native_script":null,"month_format_abbreviated":["tammikuuta","helmikuuta","maaliskuuta","huhtikuuta","toukokuuta","kesäkuuta","heinäkuuta","elokuuta","syyskuuta","lokakuuta","marraskuuta","joulukuuta"],"default_date_format_length":"medium","day_stand_alone_narrow":["M","T","K","T","P","L","S"],"day_format_abbreviated":["ma","ti","ke","to","pe","la","su"],"datetime_format_medium":"d.M.yyyy H.mm.ss"},
        misc_info = {"delimiters":{"quotation_start":"”","quotation_end":"”","alternate_quotation_start":"’","alternate_quotation_end":"’"},"orientation":{"lines":"top-to-bottom","characters":"left-to-right"},"posix":{"nostr":"ei:e","yesstr":"kyllä:k"},"plural_forms":{"category_list":["one","other"],"category_rules_function":null,"category_rules":{"one":"n is 1"},"category_rules_compiled":{"one":function (n) {if ( (( n == 1))) { return 'one'; } return;}}},"cldr_formats":{"territory":"alue: {0}","_decimal_format_decimal":",","language":"kieli: {0}","percent":"#,##0 %","locale":"{0} ({1})","_decimal_format_group":" ","_percent_format_percent":"%","decimal":"#,##0.###","ellipsis":{"medial":"{0}...{1}","final":"{0}...","initial":"...{0}"},"list_or":{"start":"{0}, {1}","middle":"{0}, {1}","end":"{0} tai {1}","2":"{0} tai {1}"},"list":{"middle":"{0}, {1}","2":"{0} ja {1}","start":"{0}, {1}","end":"{0} ja {1}"}},"fallback":[],"characters":{"more_information":"?"}};

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