//~~GENERATED~~
//-------------------------------------------------------------
// Source:    /usr/local/cpanel/base/sharedjs/sqlui.js
// Generated: /usr/local/cpanel/base/sharedjs/sqlui-tr.js
// Module:    legacy_shared/sqlui-tr
// Locale:    tr
// This file is generated by the cpanel localization system
// using the bin/_build_translated_js_hash_files.pl script.
//-------------------------------------------------------------
// !!! Do not hand edit this file !!!
//-------------------------------------------------------------
(function() {
    // The raw lexicon.
    var newLex = {"Close":"Kapat","If you change this database’s name, you will be unable to rename it back to “[_1]”. This is because the old name lacks the username prefix ([_2]) that this system requires on the names of all new databases and database users. If you require a name without the prefix, you must contact your server administrator.":"Bu veritabanının adını değiştirirseniz, tekrar “[_1]” olarak adlandıramazsınız. Bunun nedeni, eski adda, bu sistemin tüm yeni veritabanlarının ve veritabanı kullanıcılarının adlarında gerektirdiği kullanıcı adı ön ekinin ([_2]) bulunmamasıdır. Ön eksiz bir ada gereksiniminiz varsa, sunucu yöneticinizle iletişime geçmelisiniz.","If you change this user’s name, you will be unable to rename it back to “[_1]”. This is because the old name lacks the username prefix ([_2]) that this system requires on the names of all new databases and database users. If you require a name without the prefix, you must contact your server administrator.":"Bu kullanıcının adını değiştirirseniz, tekrar “[_1]” olarak adlandıramazsınız. Bunun nedeni, eski adda, bu sistemin tüm yeni veritabanlarının ve veritabanı kullanıcılarının adlarında gerektirdiği kullanıcı adı ön ekinin ([_2]) bulunmamasıdır. Ön eksiz bir ada gereksiniminiz varsa, sunucu yöneticinizle iletişime geçmelisiniz.","It is a potentially dangerous operation to rename a database. You may want to [output,url,_1,back up this database] before renaming it.":"It is a potentially dangerous operation to rename a database. You may want to [output,url,_1,back up this database] before renaming it.","Rename Database":"Veritabanını Yeniden Adlandır","Rename Database User":"Veritabanı Kullanıcısını Yeniden Adlandır","Renaming database user …":"Veritabanı kullanıcısı yeniden adlandırılıyor …","Renaming database …":"Veritabanı yeniden adlandırılıyor …","Success! The browser is now redirecting …":"Başarılı! Tarayıcı şu anda yönlendiriyor …","Success! This page will now reload.":"Başarılı! Bu sayfa şimdi yeniden yüklenecek.","The new name must be different from the old name.":"Yeni isim, eski isimden farklı olmalıdır."};

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
//~~END-GENERATED~~
