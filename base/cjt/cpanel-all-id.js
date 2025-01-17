//~~GENERATED~~
//-------------------------------------------------------------
// Source:    /usr/local/cpanel/base/cjt/cpanel-all.js
// Generated: /usr/local/cpanel/base/cjt/cpanel-all-id.js
// Module:    legacy_cjt/cpanel-all-id
// Locale:    id
// This file is generated by the cpanel localization system
// using the bin/_build_translated_js_hash_files.pl script.
//-------------------------------------------------------------
// !!! Do not hand edit this file !!!
//-------------------------------------------------------------
(function() {
    // The raw lexicon.
    var newLex = {"Advanced Options":"Opsi Lanjutan","Alpha Characters":"Karakter Alfa","An unknown error occurred.":"Terjadi kesalahan yang tidak diketahui.","Both":"Keduanya","Cancel":"Batalkan","Click to close.":"Klik untuk menutup.","Close":"Tutup","Generate Password":"Buat Kata Sandi","I have copied this password in a safe place.":"Saya telah menyalin kata sandi ini di tempat yang aman.","Length":"Panjang","Loading …":"Memuat …","Lowercase":"Huruf kecil","Non Alpha Characters":"Karakter Non-Alfa","Numbers":"Nomor","OK":"OK","Password Generator":"Pembuat Kata Sandi","Password Strength":"Kekuatan Kata Sandi","Password cannot be empty.":"Kata sandi tidak boleh kosong.","Password strength must be at least [numf,_1].":"Kekuatan kata sandi harus minimal [numf,_1].","Passwords Match":"Kecocokan Kata Sandi","Passwords do not match.":"Kata sandi tidak cocok.","Passwords must be at least [quant,_1,character,characters] long.":"Panjang kata sandi minimal [quant,_1, karakter, karakter].","Strong":"Kuat","Success!":"Berhasil!","Symbols":"Simbol","The API response could not be parsed.":"Respons API tidak dapat diurai.","Uppercase":"Huruf Kapital","Use Password":"Gunakan Kata Sandi","Validation Errors":"Validasi Salah","Very Strong":"Sangat Kuat","Very Weak":"Sangat Lemah","Weak":"Lemah","less »":"lebih sedikit »","more »":"lebih banyak »","unlimited":"tidak terbatas"};

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
// CLDR Data for id
//-------------------------------------------------------------
(function(context) {
    var locale = "id",
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
        datetime_info = {"territory":null,"quarter_stand_alone_narrow":["1","2","3","4"],"time_formats":{"short":"HH:mm","medium":"HH:mm:ss","long":"HH:mm:ss z","full":"H:mm:ss zzzz"},"era_narrow":["BCE","CE"],"datetime_format_full":"EEEE, dd MMMM yyyy H:mm:ss zzzz","glibc_date_1_format":"%a %b %e %H:%M:%S %Z %Y","datetime_format_long":"d MMMM yyyy HH:mm:ss z","date_format_short":"dd/MM/yy","native_variant":null,"name":"Indonesian","language_id":"id","era_wide":["BCE","CE"],"variant_id":null,"date_format_medium":"d MMM yyyy","time_format_default":"HH:mm:ss","era_abbreviated":["BCE","CE"],"datetime_format":"{1} {0}","month_format_wide":["Januari","Februari","Maret","April","Mei","Juni","Juli","Agustus","September","Oktober","November","Desember"],"quarter_format_abbreviated":["K1","K2","K3","K4"],"datetime_format_short":"dd/MM/yy HH:mm","glibc_datetime_format":"%a %b %e %H:%M:%S %Y","quarter_stand_alone_abbreviated":["K1","K2","K3","K4"],"script_id":null,"prefers_24_hour_time":1,"cldr_version":"1.7.1","day_format_wide":["Senin","Selasa","Rabu","Kamis","Jumat","Sabtu","Minggu"],"language":"Indonesian","month_format_narrow":["1","2","3","4","5","6","7","8","9","10","11","12"],"time_format_full":"H:mm:ss zzzz","date_format_default":"d MMM yyyy","am_pm_abbreviated":["AM","PM"],"native_territory":null,"glibc_time_12_format":"%I:%M:%S %p","month_stand_alone_wide":["Januari","Februari","Maret","April","Mei","Juni","Juli","Agustus","September","Oktober","November","Desember"],"time_format_long":"HH:mm:ss z","day_stand_alone_wide":["Senin","Selasa","Rabu","Kamis","Jumat","Sabtu","Minggu"],"variant":null,"id":"id","available_formats":null,"quarter_stand_alone_wide":["kuartal pertama","kuartal kedua","kuartal ketiga","kuartal keempat"],"time_format_medium":"HH:mm:ss","time_format_short":"HH:mm","date_format_full":"EEEE, dd MMMM yyyy","territory_id":null,"first_day_of_week":"1","glibc_date_format":"%m/%d/%y","quarter_format_wide":["kuartal pertama","kuartal kedua","kuartal ketiga","kuartal keempat"],"day_stand_alone_abbreviated":["Sen","Sel","Rab","Kam","Jum","Sab","Min"],"month_stand_alone_narrow":["1","2","3","4","5","6","7","8","9","10","11","12"],"format_for":{"yQQQ":"y QQQ","yMMMEd":"EEE, y MMM d","d":"d","y":"y","hms":"h:mm:ss a","MMMMd":"MMMM d","yMMMM":"y MMMM","ms":"mm:ss","M":"L","yM":"y-M","MEd":"E, M-d","MMM":"LLL","Md":"M-d","yQ":"y Q","yMEd":"EEE, y-M-d","Hm":"H:mm","EEEd":"d EEE","Hms":"H:mm:ss","hm":"h:mm a","MMMEd":"E MMM d","MMMMEd":"E MMMM d","MMMd":"MMM d","yMMM":"y MMM"},"quarter_format_narrow":["1","2","3","4"],"date_formats":{"short":"dd/MM/yy","medium":"d MMM yyyy","long":"d MMMM yyyy","full":"EEEE, dd MMMM yyyy"},"date_format_long":"d MMMM yyyy","month_stand_alone_abbreviated":["Jan","Feb","Mar","Apr","Mei","Jun","Jul","Agu","Sep","Okt","Nov","Des"],"native_language":"Bahasa Indonesia","datetime_format_default":"d MMM yyyy HH:mm:ss","native_name":"Bahasa Indonesia","day_format_narrow":["2","3","4","5","6","7","1"],"script":null,"default_time_format_length":"medium","glibc_time_format":"%H:%M:%S","native_script":null,"month_format_abbreviated":["Jan","Feb","Mar","Apr","Mei","Jun","Jul","Agu","Sep","Okt","Nov","Des"],"default_date_format_length":"medium","day_stand_alone_narrow":["2","3","4","5","6","7","1"],"day_format_abbreviated":["Sen","Sel","Rab","Kam","Jum","Sab","Min"],"datetime_format_medium":"d MMM yyyy HH:mm:ss"},
        misc_info = {"delimiters":{"quotation_start":"“","quotation_end":"”","alternate_quotation_start":"‘","alternate_quotation_end":"’"},"orientation":{"lines":"top-to-bottom","characters":"left-to-right"},"posix":{"nostr":"tidak:t","yesstr":"ya:y"},"plural_forms":{"category_list":["other"],"category_rules_function":null,"category_rules":{},"category_rules_compiled":{}},"cldr_formats":{"territory":"Wilayah: {0}","_decimal_format_decimal":",","language":"Bahasa: {0}","percent":"#,##0%","locale":"{0} ({1})","_decimal_format_group":".","_percent_format_percent":"%","decimal":"#,##0.###","ellipsis":{"medial":"{0}…{1}","final":"{0}…","initial":"…{0}"},"list_or":{"2":"{0} atau {1}","start":"{0}, {1}","middle":"{0}, {1}","end":"{0}, atau {1}"},"list":{"middle":"{0}, {1}","2":"{0} dan {1}","start":"{0}, {1}","end":"{0}, dan {1}"}},"fallback":[],"characters":{"more_information":"?"}};

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
