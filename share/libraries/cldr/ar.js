//-------------------------------------------------------------
// CLDR Data for ar
//-------------------------------------------------------------
(function(context) {
    var locale = "ar",
        functions = {'get_plural_form':function(n){var category;var category_values=Array.prototype.slice.call(arguments,1);var has_extra_for_zero=0;var abs_n=Math.abs(n);var category_process_order=["zero","one","two","few","many","other"];var category_rules_lookup={"one":function(n){if(((n==1))){return'one';}return;},"few":function(n){if(((parseInt(n)==n&&(n%100)>=3&&(n%100)<=10))){return'few';}return;},"zero":function(n){if(((n==0))){return'zero';}return;},"two":function(n){if(((n==2))){return'two';}return;},"many":function(n){if(((parseInt(n)==n&&(n%100)>=11&&(n%100)<=99))){return'many';}return;}};for(i=0;i<category_process_order.length;i++){if(category_rules_lookup[category_process_order[i]]){category=category_rules_lookup[category_process_order[i]](abs_n);if(category)break;}}
var categories=["one","two","few","many","zero","other"];if(category_values.length===0){category_values=categories;}
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
        datetime_info = {"territory":null,"quarter_stand_alone_narrow":["١","٢","٣","٤"],"time_formats":{"short":"h:mm a","medium":"h:mm:ss a","long":"z h:mm:ss a","full":"zzzz h:mm:ss a"},"era_narrow":["ق.م","م"],"datetime_format_full":"EEEE، d MMMM، y zzzz h:mm:ss a","glibc_date_1_format":"%a %b %e %H:%M:%S %Z %Y","datetime_format_long":"d MMMM، y z h:mm:ss a","date_format_short":"d‏/M‏/yyyy","native_variant":null,"name":"Arabic","language_id":"ar","era_wide":["قبل الميلاد","ميلادي"],"variant_id":null,"date_format_medium":"dd‏/MM‏/yyyy","time_format_default":"h:mm:ss a","era_abbreviated":["ق.م","م"],"datetime_format":"{1} {0}","month_format_wide":["يناير","فبراير","مارس","أبريل","مايو","يونيو","يوليو","أغسطس","سبتمبر","أكتوبر","نوفمبر","ديسمبر"],"quarter_format_abbreviated":["الربع الأول","الربع الثاني","الربع الثالث","الربع الرابع"],"datetime_format_short":"d‏/M‏/yyyy h:mm a","glibc_datetime_format":"%a %b %e %H:%M:%S %Y","quarter_stand_alone_abbreviated":["الربع الأول","الربع الثاني","الربع الثالث","الربع الرابع"],"script_id":null,"prefers_24_hour_time":0,"cldr_version":"1.7.1","day_format_wide":["الإثنين","الثلاثاء","الأربعاء","الخميس","الجمعة","السبت","الأحد"],"language":"Arabic","month_format_narrow":["ي","ف","م","أ","و","ن","ل","غ","س","ك","ب","د"],"time_format_full":"zzzz h:mm:ss a","date_format_default":"dd‏/MM‏/yyyy","am_pm_abbreviated":["ص","م"],"native_territory":null,"glibc_time_12_format":"%I:%M:%S %p","month_stand_alone_wide":["يناير","فبراير","مارس","أبريل","مايو","يونيو","يوليو","أغسطس","سبتمبر","أكتوبر","نوفمبر","ديسمبر"],"time_format_long":"z h:mm:ss a","day_stand_alone_wide":["الإثنين","الثلاثاء","الأربعاء","الخميس","الجمعة","السبت","الأحد"],"variant":null,"id":"ar","available_formats":null,"quarter_stand_alone_wide":["الربع الأول","الربع الثاني","الربع الثالث","الربع الرابع"],"time_format_medium":"h:mm:ss a","time_format_short":"h:mm a","date_format_full":"EEEE، d MMMM، y","territory_id":null,"first_day_of_week":"1","glibc_date_format":"%m/%d/%y","quarter_format_wide":["الربع الأول","الربع الثاني","الربع الثالث","الربع الرابع"],"day_stand_alone_abbreviated":["إثنين","ثلاثاء","أربعاء","خميس","جمعة","سبت","أحد"],"month_stand_alone_narrow":["ي","ف","م","أ","و","ن","ل","غ","س","ك","ب","د"],"format_for":{"yQQQ":"y QQQ","yMMMEd":"EEE، d MMMM y","d":"d","y":"y","hms":"h:mm:ss a","MMMMd":"d MMMM","yMMMM":"MMMM y","ms":"mm:ss","M":"L","yM":"M‏/yyyy","MEd":"E، d-M","MMM":"LLL","Md":"d/‏M","yQ":"yyyy Q","yMEd":"EEE، d/‏M/‏yyyy","Hm":"H:mm","EEEd":"d EEE","Hms":"H:mm:ss","hm":"h:mm a","MMMEd":"E d MMM","MMMMEd":"E d MMMM","MMMd":"d MMM","yMMM":"MMM y"},"quarter_format_narrow":["١","٢","٣","٤"],"date_formats":{"short":"d‏/M‏/yyyy","medium":"dd‏/MM‏/yyyy","long":"d MMMM، y","full":"EEEE، d MMMM، y"},"date_format_long":"d MMMM، y","month_stand_alone_abbreviated":["يناير","فبراير","مارس","أبريل","مايو","يونيو","يوليو","أغسطس","سبتمبر","أكتوبر","نوفمبر","ديسمبر"],"native_language":"العربية","datetime_format_default":"dd‏/MM‏/yyyy h:mm:ss a","native_name":"العربية","day_format_narrow":["ن","ث","ر","خ","ج","س","ح"],"script":null,"default_time_format_length":"medium","glibc_time_format":"%H:%M:%S","native_script":null,"month_format_abbreviated":["يناير","فبراير","مارس","أبريل","مايو","يونيو","يوليو","أغسطس","سبتمبر","أكتوبر","نوفمبر","ديسمبر"],"default_date_format_length":"medium","day_stand_alone_narrow":["ن","ث","ر","خ","ج","س","ح"],"day_format_abbreviated":["إثنين","ثلاثاء","أربعاء","خميس","جمعة","سبت","أحد"],"datetime_format_medium":"dd‏/MM‏/yyyy h:mm:ss a"},
        misc_info = {"delimiters":{"quotation_start":"“","quotation_end":"”","alternate_quotation_start":"‘","alternate_quotation_end":"’"},"orientation":{"lines":"top-to-bottom","characters":"right-to-left"},"posix":{"nostr":"لا:ل","yesstr":"نعم:ن"},"plural_forms":{"category_list":["one","two","few","many","zero","other"],"category_rules_function":null,"category_rules":{"one":"n is 1","few":"n mod 100 in 3..10","zero":"n is 0","two":"n is 2","many":"n mod 100 in 11..99"},"category_rules_compiled":{"one":function (n) {if ( (( n == 1))) { return 'one'; } return;},"few":function (n) {if ( (( parseInt(n) == n && (n % 100) >= 3 && (n % 100) <= 10 ))) { return 'few'; } return;},"zero":function (n) {if ( (( n == 0))) { return 'zero'; } return;},"two":function (n) {if ( (( n == 2))) { return 'two'; } return;},"many":function (n) {if ( (( parseInt(n) == n && (n % 100) >= 11 && (n % 100) <= 99 ))) { return 'many'; } return;}}},"cldr_formats":{"territory":"المنطقة: {0}","_decimal_format_decimal":"٫","language":"اللغة: {0}","percent":"#,##0%","locale":"{0} ({1})","_decimal_format_group":"٬","_percent_format_percent":"٪","decimal":"#,##0.###;#,##0.###-","ellipsis":{"medial":"{0}…{1}","final":"{0}…","initial":"…{0}"},"list_or":{"middle":"{0} و{1}","end":"{0} أو {1}","start":"{0} و{1}","2":"{0} أو {1}"},"list":{"middle":"{0}، {1}","2":"{0} و {1}","start":"{0}، {1}","end":"{0}، و {1}"}},"fallback":[],"characters":{"more_information":"?"}};

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