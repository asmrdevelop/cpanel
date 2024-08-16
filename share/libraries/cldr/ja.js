//-------------------------------------------------------------
// CLDR Data for ja
//-------------------------------------------------------------
(function(context) {
    var locale = "ja",
        functions = {'get_plural_form':function(n){var category;var category_values=Array.prototype.slice.call(arguments,1);var has_extra_for_zero=0;var abs_n=Math.abs(n);var category_process_order=["zero","one","two","few","many","other"];var category_rules_lookup={};for(i=0;i<category_process_order.length;i++){if(category_rules_lookup[category_process_order[i]]){category=category_rules_lookup[category_process_order[i]](abs_n);if(category)break;}}
var categories=["other"];if(category_values.length===0){category_values=categories;}
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
        datetime_info = {"territory":null,"quarter_stand_alone_narrow":["1","2","3","4"],"time_formats":{"short":"H:mm","medium":"H:mm:ss","long":"HH:mm:ss z","full":"H時mm分ss秒 zzzz"},"era_narrow":["紀元前","西暦"],"datetime_format_full":"y年M月d日EEEEH時mm分ss秒 zzzz","glibc_date_1_format":"%a %b %e %H:%M:%S %Z %Y","datetime_format_long":"y年M月d日HH:mm:ss z","date_format_short":"yy/MM/dd","native_variant":null,"name":"Japanese","language_id":"ja","era_wide":["紀元前","西暦"],"variant_id":null,"date_format_medium":"yyyy/MM/dd","time_format_default":"H:mm:ss","era_abbreviated":["紀元前","西暦"],"datetime_format":"{1}{0}","month_format_wide":["1月","2月","3月","4月","5月","6月","7月","8月","9月","10月","11月","12月"],"quarter_format_abbreviated":["Q1","Q2","Q3","Q4"],"datetime_format_short":"yy/MM/ddH:mm","glibc_datetime_format":"%a %b %e %H:%M:%S %Y","quarter_stand_alone_abbreviated":["Q1","Q2","Q3","Q4"],"script_id":null,"prefers_24_hour_time":1,"cldr_version":"1.7.1","day_format_wide":["月曜日","火曜日","水曜日","木曜日","金曜日","土曜日","日曜日"],"language":"Japanese","month_format_narrow":["1","2","3","4","5","6","7","8","9","10","11","12"],"time_format_full":"H時mm分ss秒 zzzz","date_format_default":"yyyy/MM/dd","am_pm_abbreviated":["午前","午後"],"native_territory":null,"glibc_time_12_format":"%I:%M:%S %p","month_stand_alone_wide":["1月","2月","3月","4月","5月","6月","7月","8月","9月","10月","11月","12月"],"time_format_long":"HH:mm:ss z","day_stand_alone_wide":["月曜日","火曜日","水曜日","木曜日","金曜日","土曜日","日曜日"],"variant":null,"id":"ja","available_formats":null,"quarter_stand_alone_wide":["第1四半期","第2四半期","第3四半期","第4四半期"],"time_format_medium":"H:mm:ss","time_format_short":"H:mm","date_format_full":"y年M月d日EEEE","territory_id":null,"first_day_of_week":"1","glibc_date_format":"%m/%d/%y","quarter_format_wide":["第1四半期","第2四半期","第3四半期","第4四半期"],"day_stand_alone_abbreviated":["月","火","水","木","金","土","日"],"month_stand_alone_narrow":["1","2","3","4","5","6","7","8","9","10","11","12"],"format_for":{"yQQQ":"yQQQ","yMMMEd":"y年M月d日(EEE)","d":"d日","y":"y","hms":"ah:mm:ss","MMMMd":"M月d日","yMMMM":"y年M月","ms":"mm:ss","M":"L","yM":"y/M","MEd":"M/d(E)","MMM":"LLL","Md":"M/d","yQ":"y/Q","yMEd":"y/M/d(EEE)","Hm":"H:mm","EEEd":"d EEE","Hms":"H:mm:ss","hm":"ah:mm","MMMEd":"M月d日(E)","MMMMEd":"M月d日(E)","MMMd":"M月d日","yMMM":"y年M月"},"quarter_format_narrow":["1","2","3","4"],"date_formats":{"short":"yy/MM/dd","medium":"yyyy/MM/dd","long":"y年M月d日","full":"y年M月d日EEEE"},"date_format_long":"y年M月d日","month_stand_alone_abbreviated":["1月","2月","3月","4月","5月","6月","7月","8月","9月","10月","11月","12月"],"native_language":"日本語","datetime_format_default":"yyyy/MM/ddH:mm:ss","native_name":"日本語","day_format_narrow":["月","火","水","木","金","土","日"],"script":null,"default_time_format_length":"medium","glibc_time_format":"%H:%M:%S","native_script":null,"month_format_abbreviated":["1月","2月","3月","4月","5月","6月","7月","8月","9月","10月","11月","12月"],"default_date_format_length":"medium","day_stand_alone_narrow":["月","火","水","木","金","土","日"],"day_format_abbreviated":["月","火","水","木","金","土","日"],"datetime_format_medium":"yyyy/MM/ddH:mm:ss"},
        misc_info = {"delimiters":{"quotation_start":"「","quotation_end":"」","alternate_quotation_start":"『","alternate_quotation_end":"』"},"orientation":{"lines":"top-to-bottom","characters":"left-to-right"},"posix":{"nostr":"いいえ:イイエ","yesstr":"はい:ハイ"},"plural_forms":{"category_list":["other"],"category_rules_function":null,"category_rules":{},"category_rules_compiled":{}},"cldr_formats":{"territory":"地域: {0}","_decimal_format_decimal":".","language":"言語: {0}","percent":"#,##0%","locale":"{0}({1})","_decimal_format_group":",","_percent_format_percent":"%","decimal":"#,##0.###","ellipsis":{"medial":"{0}...{1}","final":"{0}...","initial":"...{0}"},"list_or":{"start":"{0}、{1}","end":"{0}、または{1}","middle":"{0}、{1}","2":"{0}または{1}"},"list":{"middle":"{0}、{1}","2":"{0}、{1}","start":"{0}、{1}","end":"{0}、{1}"}},"fallback":[],"characters":{"more_information":"?"}};

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