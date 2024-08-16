//-------------------------------------------------------------
// CLDR Data for ro
//-------------------------------------------------------------
(function(context) {
    var locale = "ro",
        functions = {'get_plural_form':function(n){var category;var category_values=Array.prototype.slice.call(arguments,1);var has_extra_for_zero=0;var abs_n=Math.abs(n);var category_process_order=["zero","one","two","few","many","other"];var category_rules_lookup={"one":function(n){if(((n==1))){return'one';}return;},"few":function(n){if(((n==0))||((n!=1)&&(parseInt(n)==n&&(n%100)>=1&&(n%100)<=19))){return'few';}return;}};for(i=0;i<category_process_order.length;i++){if(category_rules_lookup[category_process_order[i]]){category=category_rules_lookup[category_process_order[i]](abs_n);if(category)break;}}
var categories=["one","few","other"];if(category_values.length===0){category_values=categories;}
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
        datetime_info = {"territory":null,"quarter_stand_alone_narrow":["T1","T2","T3","T4"],"time_formats":{"short":"HH:mm","medium":"HH:mm:ss","long":"HH:mm:ss z","full":"HH:mm:ss zzzz"},"era_narrow":["î.Hr.","d.Hr."],"datetime_format_full":"EEEE, d MMMM y, HH:mm:ss zzzz","glibc_date_1_format":"%a %b %e %H:%M:%S %Z %Y","datetime_format_long":"d MMMM y, HH:mm:ss z","date_format_short":"dd.MM.yyyy","native_variant":null,"name":"Romanian","language_id":"ro","era_wide":["înainte de Hristos","după Hristos"],"variant_id":null,"date_format_medium":"dd.MM.yyyy","time_format_default":"HH:mm:ss","era_abbreviated":["î.Hr.","d.Hr."],"datetime_format":"{1}, {0}","month_format_wide":["ianuarie","februarie","martie","aprilie","mai","iunie","iulie","august","septembrie","octombrie","noiembrie","decembrie"],"quarter_format_abbreviated":["trim. I","trim. II","trim. III","trim. IV"],"datetime_format_short":"dd.MM.yyyy, HH:mm","glibc_datetime_format":"%a %b %e %H:%M:%S %Y","quarter_stand_alone_abbreviated":["trim. I","trim. II","trim. III","trim. IV"],"script_id":null,"prefers_24_hour_time":1,"cldr_version":"1.7.1","day_format_wide":["luni","marți","miercuri","joi","vineri","sâmbătă","duminică"],"language":"Romanian","month_format_narrow":["I","F","M","A","M","I","I","A","S","O","N","D"],"time_format_full":"HH:mm:ss zzzz","date_format_default":"dd.MM.yyyy","am_pm_abbreviated":["AM","PM"],"native_territory":null,"glibc_time_12_format":"%I:%M:%S %p","month_stand_alone_wide":["ianuarie","februarie","martie","aprilie","mai","iunie","iulie","august","septembrie","octombrie","noiembrie","decembrie"],"time_format_long":"HH:mm:ss z","day_stand_alone_wide":["luni","marți","miercuri","joi","vineri","sâmbătă","duminică"],"variant":null,"id":"ro","available_formats":null,"quarter_stand_alone_wide":["trimestrul I","trimestrul al II-lea","trimestrul al III-lea","trimestrul al IV-lea"],"time_format_medium":"HH:mm:ss","time_format_short":"HH:mm","date_format_full":"EEEE, d MMMM y","territory_id":null,"first_day_of_week":"1","glibc_date_format":"%m/%d/%y","quarter_format_wide":["trimestrul I","trimestrul al II-lea","trimestrul al III-lea","trimestrul al IV-lea"],"day_stand_alone_abbreviated":["Lu","Ma","Mi","Jo","Vi","Sâ","Du"],"month_stand_alone_narrow":["I","F","M","A","M","I","I","A","S","O","N","D"],"format_for":{"yQQQ":"QQQ y","yMMMEd":"EEE, d MMM y","d":"d","y":"y","hms":"h:mm:ss a","MMMMd":"d MMMM","yMMMM":"MMMM y","ms":"mm:ss","M":"L","yM":"M.yyyy","MEd":"E, d MMM","MMM":"LLL","Md":"d.M","yQ":"'trimestrul' Q y","yMEd":"EEE, d/M/yyyy","Hm":"H:mm","EEEd":"EEE d","Hms":"H:mm:ss","hm":"h:mm a","MMMEd":"E, d MMM","MMMMEd":"E, d MMMM","MMMd":"d MMM","yMMM":"MMM y"},"quarter_format_narrow":["T1","T2","T3","T4"],"date_formats":{"short":"dd.MM.yyyy","medium":"dd.MM.yyyy","long":"d MMMM y","full":"EEEE, d MMMM y"},"date_format_long":"d MMMM y","month_stand_alone_abbreviated":["ian.","feb.","mar.","apr.","mai","iun.","iul.","aug.","sept.","oct.","nov.","dec."],"native_language":"română","datetime_format_default":"dd.MM.yyyy, HH:mm:ss","native_name":"română","day_format_narrow":["L","M","M","J","V","S","D"],"script":null,"default_time_format_length":"medium","glibc_time_format":"%H:%M:%S","native_script":null,"month_format_abbreviated":["ian.","feb.","mar.","apr.","mai","iun.","iul.","aug.","sept.","oct.","nov.","dec."],"default_date_format_length":"medium","day_stand_alone_narrow":["L","M","M","J","V","S","D"],"day_format_abbreviated":["Lu","Ma","Mi","Jo","Vi","Sâ","Du"],"datetime_format_medium":"dd.MM.yyyy, HH:mm:ss"},
        misc_info = {"delimiters":{"quotation_start":"„","quotation_end":"”","alternate_quotation_start":"«","alternate_quotation_end":"»"},"orientation":{"lines":"top-to-bottom","characters":"left-to-right"},"posix":{"nostr":"nu:n","yesstr":"da:d"},"plural_forms":{"category_list":["one","few","other"],"category_rules_function":null,"category_rules":{"one":"n is 1","few":"n is 0 OR n is not 1 AND n mod 100 in 1..19"},"category_rules_compiled":{"one":function (n) {if ( (( n == 1))) { return 'one'; } return;},"few":function (n) {if ( (( n == 0)) ||  (( n != 1) && ( parseInt(n) == n && (n % 100) >= 1 && (n % 100) <= 19 ))) { return 'few'; } return;}}},"cldr_formats":{"territory":"Regiune: {0}","_decimal_format_decimal":",","language":"Limbă: {0}","percent":"#,##0%","locale":"{0} ({1})","_decimal_format_group":".","_percent_format_percent":"%","decimal":"#,##0.###","ellipsis":{"medial":"{0}…{1}","final":"{0}…","initial":"…{0}"},"list_or":{"middle":"{0}, {1}","end":"{0} sau {1}","start":"{0}, {1}","2":"{0} sau {1}"},"list":{"middle":"{0}, {1}","2":"{0} şi {1}","start":"{0}, {1}","end":"{0} şi {1}"}},"fallback":[],"characters":{"more_information":"?"}};

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