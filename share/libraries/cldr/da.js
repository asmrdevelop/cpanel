//-------------------------------------------------------------
// CLDR Data for da
//-------------------------------------------------------------
(function(context) {
    var locale = "da",
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
        datetime_info = {"territory":null,"quarter_stand_alone_narrow":["1","2","3","4"],"time_formats":{"short":"HH.mm","medium":"HH.mm.ss","long":"HH:mm:ss z","full":"HH.mm.ss zzzz"},"era_narrow":["f.Kr.","e.Kr."],"datetime_format_full":"EEEE 'den' d. MMMM y HH.mm.ss zzzz","glibc_date_1_format":"%a %b %e %H:%M:%S %Z %Y","datetime_format_long":"d. MMM y HH:mm:ss z","date_format_short":"dd/MM/yy","native_variant":null,"name":"Danish","language_id":"da","era_wide":["f.Kr.","e.Kr."],"variant_id":null,"date_format_medium":"dd/MM/yyyy","time_format_default":"HH.mm.ss","era_abbreviated":["f.Kr.","e.Kr."],"datetime_format":"{1} {0}","month_format_wide":["januar","februar","marts","april","maj","juni","juli","august","september","oktober","november","december"],"quarter_format_abbreviated":["K1","K2","K3","K4"],"datetime_format_short":"dd/MM/yy HH.mm","glibc_datetime_format":"%a %b %e %H:%M:%S %Y","quarter_stand_alone_abbreviated":["K1","K2","K3","K4"],"script_id":null,"prefers_24_hour_time":1,"cldr_version":"1.7.1","day_format_wide":["mandag","tirsdag","onsdag","torsdag","fredag","lørdag","søndag"],"language":"Danish","month_format_narrow":["J","F","M","A","M","J","J","A","S","O","N","D"],"time_format_full":"HH.mm.ss zzzz","date_format_default":"dd/MM/yyyy","am_pm_abbreviated":["f.m.","e.m."],"native_territory":null,"glibc_time_12_format":"%I:%M:%S %p","month_stand_alone_wide":["januar","februar","marts","april","maj","juni","juli","august","september","oktober","november","december"],"time_format_long":"HH:mm:ss z","day_stand_alone_wide":["mandag","tirsdag","onsdag","torsdag","fredag","lørdag","søndag"],"variant":null,"id":"da","available_formats":null,"quarter_stand_alone_wide":["1. kvartal","2. kvartal","3. kvartal","4. kvartal"],"time_format_medium":"HH.mm.ss","time_format_short":"HH.mm","date_format_full":"EEEE 'den' d. MMMM y","territory_id":null,"first_day_of_week":"1","glibc_date_format":"%m/%d/%y","quarter_format_wide":["1. kvartal","2. kvartal","3. kvartal","4. kvartal"],"day_stand_alone_abbreviated":["man","tir","ons","tor","fre","lør","søn"],"month_stand_alone_narrow":["J","F","M","A","M","J","J","A","S","O","N","D"],"format_for":{"yQQQ":"QQQ y","yMMMEd":"EEE. d. MMM y","d":"d.","y":"y","hms":"h.mm.ss a","MMMMd":"d. MMMM","yMMMM":"MMMM y","ms":"mm.ss","M":"M","yM":"M-yyyy","MEd":"E. d-M","MMM":"MMM","Md":"d/M","yQ":"Q yyyy","yMEd":"EEE. d-M-yyyy","Hm":"HH.mm","EEEd":"d EEE","Hms":"H:mm:ss","hm":"h.mm a","MMMEd":"E d MMM","MMMMEd":"E, d. MMMM","MMMd":"d. MMM","yMMM":"MMM y"},"quarter_format_narrow":["1","2","3","4"],"date_formats":{"short":"dd/MM/yy","medium":"dd/MM/yyyy","long":"d. MMM y","full":"EEEE 'den' d. MMMM y"},"date_format_long":"d. MMM y","month_stand_alone_abbreviated":["jan","feb","mar","apr","maj","jun","jul","aug","sep","okt","nov","dec"],"native_language":"dansk","datetime_format_default":"dd/MM/yyyy HH.mm.ss","native_name":"dansk","day_format_narrow":["M","T","O","T","F","L","S"],"script":null,"default_time_format_length":"medium","glibc_time_format":"%H:%M:%S","native_script":null,"month_format_abbreviated":["jan.","feb.","mar.","apr.","maj","jun.","jul.","aug.","sep.","okt.","nov.","dec."],"default_date_format_length":"medium","day_stand_alone_narrow":["M","T","O","T","F","L","S"],"day_format_abbreviated":["man","tir","ons","tor","fre","lør","søn"],"datetime_format_medium":"dd/MM/yyyy HH.mm.ss"},
        misc_info = {"delimiters":{"quotation_start":"”","quotation_end":"”","alternate_quotation_start":"”","alternate_quotation_end":"”"},"orientation":{"lines":"top-to-bottom","characters":"left-to-right"},"posix":{"nostr":"nej:n","yesstr":"ja:j"},"plural_forms":{"category_list":["one","other"],"category_rules_function":null,"category_rules":{"one":"n is 1"},"category_rules_compiled":{"one":function (n) {if ( (( n == 1))) { return 'one'; } return;}}},"cldr_formats":{"territory":"Område: {0}","_decimal_format_decimal":",","language":"Sprog: {0}","percent":"#,##0 %","locale":"{0} ({1})","_decimal_format_group":".","_percent_format_percent":"%","decimal":"#,##0.###","ellipsis":{"medial":"{0}…{1}","final":"{0}…","initial":"…{0}"},"list_or":{"2":"{0} eller {1}","end":"{0} eller {1}","middle":"{0}, {1}","start":"{0}, {1}"},"list":{"middle":"{0}, {1}","2":"{0} og {1}","start":"{0}, {1}","end":"{0} og {1}"}},"fallback":["nb","nn","sv","en"],"characters":{"more_information":"?"}};

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