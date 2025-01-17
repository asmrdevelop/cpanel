//~~GENERATED~~
//-------------------------------------------------------------
// Source:    /usr/local/cpanel/base/frontend/jupiter/_assets/master.cmb.js
// Generated: /usr/local/cpanel/base/frontend/jupiter/_assets/master.cmb-ko.js
// Module:    /jupiter/_assets/master.cmb-ko
// Locale:    ko
// This file is generated by the cpanel localization system
// using the bin/_build_translated_js_hash_files.pl script.
//-------------------------------------------------------------
// !!! Do not hand edit this file !!!
//-------------------------------------------------------------
(function() {
    // The raw lexicon.
    var newLex = {"[quant,_1,%s byte,%s bytes]":"[quant,_1,%s 바이트,%s 바이트]"};

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
// CLDR Data for ko
//-------------------------------------------------------------
(function(context) {
    var locale = "ko",
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
        datetime_info = {"territory":null,"quarter_stand_alone_narrow":["1","2","3","4"],"time_formats":{"short":"a h:mm","medium":"a h:mm:ss","long":"a hh시 mm분 ss초 z","full":"a hh시 mm분 ss초 zzzz"},"era_narrow":["기원전","서기"],"datetime_format_full":"y년 M월 d일 EEEEa hh시 mm분 ss초 zzzz","glibc_date_1_format":"%a %b %e %H:%M:%S %Z %Y","datetime_format_long":"y년 M월 d일a hh시 mm분 ss초 z","date_format_short":"yy. M. d.","native_variant":null,"name":"Korean","language_id":"ko","era_wide":["서력기원전","서력기원"],"variant_id":null,"date_format_medium":"yyyy. M. d.","time_format_default":"a h:mm:ss","era_abbreviated":["기원전","서기"],"datetime_format":"{1}{0}","month_format_wide":["1월","2월","3월","4월","5월","6월","7월","8월","9월","10월","11월","12월"],"quarter_format_abbreviated":["1분기","2분기","3분기","4분기"],"datetime_format_short":"yy. M. d.a h:mm","glibc_datetime_format":"%a %b %e %H:%M:%S %Y","quarter_stand_alone_abbreviated":["1분기","2분기","3분기","4분기"],"script_id":null,"prefers_24_hour_time":0,"cldr_version":"1.7.1","day_format_wide":["월요일","화요일","수요일","목요일","금요일","토요일","일요일"],"language":"Korean","month_format_narrow":["1월","2월","3월","4월","5월","6월","7월","8월","9월","10월","11월","12월"],"time_format_full":"a hh시 mm분 ss초 zzzz","date_format_default":"yyyy. M. d.","am_pm_abbreviated":["오전","오후"],"native_territory":null,"glibc_time_12_format":"%I:%M:%S %p","month_stand_alone_wide":["1월","2월","3월","4월","5월","6월","7월","8월","9월","10월","11월","12월"],"time_format_long":"a hh시 mm분 ss초 z","day_stand_alone_wide":["월요일","화요일","수요일","목요일","금요일","토요일","일요일"],"variant":null,"id":"ko","available_formats":null,"quarter_stand_alone_wide":["제 1/4분기","제 2/4분기","제 3/4분기","제 4/4분기"],"time_format_medium":"a h:mm:ss","time_format_short":"a h:mm","date_format_full":"y년 M월 d일 EEEE","territory_id":null,"first_day_of_week":"1","glibc_date_format":"%m/%d/%y","quarter_format_wide":["제 1/4분기","제 2/4분기","제 3/4분기","제 4/4분기"],"day_stand_alone_abbreviated":["월","화","수","목","금","토","일"],"month_stand_alone_narrow":["1월","2월","3월","4월","5월","6월","7월","8월","9월","10월","11월","12월"],"format_for":{"yQQQ":"y년 QQQ","yMMMEd":"y년 MMM d일 EEE","d":"d","y":"y","hms":"h:mm:ss a","MMMMd":"MMMM d일","yMMMM":"y년 MMMM","ms":"mm:ss","M":"L","yM":"yyyy. M.","MEd":"M. d. (E)","MMM":"LLL","Md":"M. d.","yQ":"y년 Q분기","yMEd":"yyyy. M. d. EEE","Hm":"H:mm","EEEd":"d일 EEE","Hms":"H시 m분 s초","hm":"h:mm a","MMMEd":"MMM d일 (E)","MMMMEd":"MMMM d일 (E)","MMMd":"MMM d일","yMMM":"y년 MMM"},"quarter_format_narrow":["1","2","3","4"],"date_formats":{"short":"yy. M. d.","medium":"yyyy. M. d.","long":"y년 M월 d일","full":"y년 M월 d일 EEEE"},"date_format_long":"y년 M월 d일","month_stand_alone_abbreviated":["1","2","3","4","5","6","7","8","9","10","11","12"],"native_language":"한국어","datetime_format_default":"yyyy. M. d.a h:mm:ss","native_name":"한국어","day_format_narrow":["월","화","수","목","금","토","일"],"script":null,"default_time_format_length":"medium","glibc_time_format":"%H:%M:%S","native_script":null,"month_format_abbreviated":["1월","2월","3월","4월","5월","6월","7월","8월","9월","10월","11월","12월"],"default_date_format_length":"medium","day_stand_alone_narrow":["월","화","수","목","금","토","일"],"day_format_abbreviated":["월","화","수","목","금","토","일"],"datetime_format_medium":"yyyy. M. d.a h:mm:ss"},
        misc_info = {"delimiters":{"quotation_start":"‘","quotation_end":"’","alternate_quotation_start":"“","alternate_quotation_end":"”"},"orientation":{"lines":"top-to-bottom","characters":"left-to-right"},"posix":{"nostr":"아니오","yesstr":"예"},"plural_forms":{"category_list":["other"],"category_rules_function":null,"category_rules":{},"category_rules_compiled":{}},"cldr_formats":{"territory":"지역: {0}","_decimal_format_decimal":".","language":"언어: {0}","percent":"#,##0%","locale":"{0}({1})","_decimal_format_group":",","_percent_format_percent":"%","decimal":"#,##0.###","ellipsis":{"medial":"{0}...{1}","final":"{0}…","initial":"…{0}"},"list_or":{"start":"{0}, {1}","end":"{0} 또는 {1}","middle":"{0}, {1}","2":"{0} 또는 {1}"},"list":{"middle":"{0}, {1}","2":"{0} 및 {1}","start":"{0}, {1}","end":"{0} 및 {1}"}},"fallback":[],"characters":{"more_information":"?"}};

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
