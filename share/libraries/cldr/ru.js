//-------------------------------------------------------------
// CLDR Data for ru
//-------------------------------------------------------------
(function(context) {
    var locale = "ru",
        functions = {'get_plural_form':function(n){var category;var category_values=Array.prototype.slice.call(arguments,1);var has_extra_for_zero=0;var abs_n=Math.abs(n);var category_process_order=["zero","one","two","few","many","other"];var category_rules_lookup={"one":function(n){if((((n%10)==1)&&((n%100)!=11))){return'one';}return;},"few":function(n){if(((parseInt(n)==n&&(n%10)>=2&&(n%10)<=4)&&(parseInt(n)!=n||(n%100)<12||(n%100)>14))){return'few';}return;},"many":function(n){if((((n%10)==0))||((parseInt(n)==n&&(n%10)>=5&&(n%10)<=9))||((parseInt(n)==n&&(n%100)>=11&&(n%100)<=14))){return'many';}return;}};for(i=0;i<category_process_order.length;i++){if(category_rules_lookup[category_process_order[i]]){category=category_rules_lookup[category_process_order[i]](abs_n);if(category)break;}}
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
        datetime_info = {"territory":null,"quarter_stand_alone_narrow":["1","2","3","4"],"time_formats":{"short":"H:mm","medium":"H:mm:ss","long":"H:mm:ss z","full":"H:mm:ss zzzz"},"era_narrow":["до н.э.","н.э."],"datetime_format_full":"EEEE, d MMMM y 'г'. H:mm:ss zzzz","glibc_date_1_format":"%a %b %e %H:%M:%S %Z %Y","datetime_format_long":"d MMMM y 'г'. H:mm:ss z","date_format_short":"dd.MM.yy","native_variant":null,"name":"Russian","language_id":"ru","era_wide":["до н.э.","н.э."],"variant_id":null,"date_format_medium":"dd.MM.yyyy","time_format_default":"H:mm:ss","era_abbreviated":["до н.э.","н.э."],"datetime_format":"{1} {0}","month_format_wide":["января","февраля","марта","апреля","мая","июня","июля","августа","сентября","октября","ноября","декабря"],"quarter_format_abbreviated":["1-й кв.","2-й кв.","3-й кв.","4-й кв."],"datetime_format_short":"dd.MM.yy H:mm","glibc_datetime_format":"%a %b %e %H:%M:%S %Y","quarter_stand_alone_abbreviated":["1-й кв.","2-й кв.","3-й кв.","4-й кв."],"script_id":null,"prefers_24_hour_time":1,"cldr_version":"1.7.1","day_format_wide":["понедельник","вторник","среда","четверг","пятница","суббота","воскресенье"],"language":"Russian","month_format_narrow":["Я","Ф","М","А","М","И","И","А","С","О","Н","Д"],"time_format_full":"H:mm:ss zzzz","date_format_default":"dd.MM.yyyy","am_pm_abbreviated":["AM","PM"],"native_territory":null,"glibc_time_12_format":"%I:%M:%S %p","month_stand_alone_wide":["Январь","Февраль","Март","Апрель","Май","Июнь","Июль","Август","Сентябрь","Октябрь","Ноябрь","Декабрь"],"time_format_long":"H:mm:ss z","day_stand_alone_wide":["Понедельник","Вторник","Среда","Четверг","Пятница","Суббота","Воскресенье"],"variant":null,"id":"ru","available_formats":null,"quarter_stand_alone_wide":["1-й квартал","2-й квартал","3-й квартал","4-й квартал"],"time_format_medium":"H:mm:ss","time_format_short":"H:mm","date_format_full":"EEEE, d MMMM y 'г'.","territory_id":null,"first_day_of_week":"1","glibc_date_format":"%m/%d/%y","quarter_format_wide":["1-й квартал","2-й квартал","3-й квартал","4-й квартал"],"day_stand_alone_abbreviated":["Пн","Вт","Ср","Чт","Пт","Сб","Вс"],"month_stand_alone_narrow":["Я","Ф","М","А","М","И","И","А","С","О","Н","Д"],"format_for":{"yQQQ":"y QQQ","yMMMEd":"E, d MMM y","d":"d","y":"y","hms":"h:mm:ss a","MMMMd":"d MMMM","yMMMM":"MMMM y","ms":"mm:ss","M":"L","yM":"yyyy-M","MEd":"E, M-d","MMM":"LLL","Md":"d.M","yQ":"Q y","yMEd":"EEE, yyyy-M-d","Hm":"H:mm","EEEd":"d EEE","Hms":"H:mm:ss","hm":"h:mm a","MMMEd":"E MMM d","MMMMEd":"E MMMM d","MMMd":"d MMM","yMMM":"MMM y"},"quarter_format_narrow":["1","2","3","4"],"date_formats":{"short":"dd.MM.yy","medium":"dd.MM.yyyy","long":"d MMMM y 'г'.","full":"EEEE, d MMMM y 'г'."},"date_format_long":"d MMMM y 'г'.","month_stand_alone_abbreviated":["янв.","февр.","март","апр.","май","июнь","июль","авг.","сент.","окт.","нояб.","дек."],"native_language":"русский","datetime_format_default":"dd.MM.yyyy H:mm:ss","native_name":"русский","day_format_narrow":["П","В","С","Ч","П","С","В"],"script":null,"default_time_format_length":"medium","glibc_time_format":"%H:%M:%S","native_script":null,"month_format_abbreviated":["янв.","февр.","марта","апр.","мая","июня","июля","авг.","сент.","окт.","нояб.","дек."],"default_date_format_length":"medium","day_stand_alone_narrow":["П","В","С","Ч","П","С","В"],"day_format_abbreviated":["Пн","Вт","Ср","Чт","Пт","Сб","Вс"],"datetime_format_medium":"dd.MM.yyyy H:mm:ss"},
        misc_info = {"delimiters":{"quotation_start":"«","quotation_end":"»","alternate_quotation_start":"„","alternate_quotation_end":"“"},"orientation":{"lines":"top-to-bottom","characters":"left-to-right"},"posix":{"nostr":"нет:н","yesstr":"да:д"},"plural_forms":{"category_list":["one","few","many","other"],"category_rules_function":null,"category_rules":{"one":"n mod 10 is 1 and n mod 100 is not 11","few":"n mod 10 in 2..4 and n mod 100 not in 12..14","many":"n mod 10 is 0 or n mod 10 in 5..9 or n mod 100 in 11..14"},"category_rules_compiled":{"one":function (n) {if ( (( (n % 10) == 1) && ( (n % 100) != 11))) { return 'one'; } return;},"few":function (n) {if ( (( parseInt(n) == n && (n % 10) >= 2 && (n % 10) <= 4 ) && ( parseInt(n) != n || (n % 100) < 12 || (n % 100) > 14 ))) { return 'few'; } return;},"many":function (n) {if ( (( (n % 10) == 0)) ||  (( parseInt(n) == n && (n % 10) >= 5 && (n % 10) <= 9 )) ||  (( parseInt(n) == n && (n % 100) >= 11 && (n % 100) <= 14 ))) { return 'many'; } return;}}},"cldr_formats":{"territory":"Регион: {0}","_decimal_format_decimal":",","language":"Язык: {0}","percent":"#,##0 %","locale":"{0} ({1})","_decimal_format_group":" ","_percent_format_percent":"%","decimal":"#,##0.###","ellipsis":{"medial":"{0}…{1}","final":"{0}…","initial":"…{0}"},"list_or":{"start":"{0}, {1}","middle":"{0}, {1}","end":"{0} или {1}","2":"{0} или {1}"},"list":{"middle":"{0}, {1}","2":"{0} и {1}","start":"{0}, {1}","end":"{0} и {1}"}},"fallback":[],"characters":{"more_information":"?"}};

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