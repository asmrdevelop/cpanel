//~~GENERATED~~
//-------------------------------------------------------------
// Source:    /usr/local/cpanel/base/sharedjs/sqlui.js
// Generated: /usr/local/cpanel/base/sharedjs/sqlui-zh.js
// Module:    legacy_shared/sqlui-zh
// Locale:    zh
// This file is generated by the cpanel localization system
// using the bin/_build_translated_js_hash_files.pl script.
//-------------------------------------------------------------
// !!! Do not hand edit this file !!!
//-------------------------------------------------------------
(function() {
    // The raw lexicon.
    var newLex = {"Close":"关闭","If you change this database’s name, you will be unable to rename it back to “[_1]”. This is because the old name lacks the username prefix ([_2]) that this system requires on the names of all new databases and database users. If you require a name without the prefix, you must contact your server administrator.":"如果更改此数据库的名称，将无法再将其重命名为“[_1]”。 这是因为旧名称缺乏此系统要求在所有新数据库名和数据库用户名中提供的用户名前缀([_2])。 如果您需要不带前缀的名称，则必须联系服务器管理员。","If you change this user’s name, you will be unable to rename it back to “[_1]”. This is because the old name lacks the username prefix ([_2]) that this system requires on the names of all new databases and database users. If you require a name without the prefix, you must contact your server administrator.":"如果更改此用户的名称，将无法再将其重命名为“[_1]”。 这是因为旧名称缺乏此系统要求在所有新数据库名和数据库用户名中提供的用户名前缀([_2])。 如果您需要不带前缀的名称，则必须联系服务器管理员。","It is a potentially dangerous operation to rename a database. You may want to [output,url,_1,back up this database] before renaming it.":"It is a potentially dangerous operation to rename a database. You may want to [output,url,_1,back up this database] before renaming it.","Rename Database":"重命名数据库","Rename Database User":"重命名数据库用户","Renaming database user …":"正在重命名数据库用户…","Renaming database …":"正在重命名数据库…","Success! The browser is now redirecting …":"成功! 浏览器现在正在重定向…","Success! This page will now reload.":"成功! 此页面现在将重新加载。","The new name must be different from the old name.":"新名称必须与旧名称不同。"};

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