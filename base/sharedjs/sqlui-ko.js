//~~GENERATED~~
//-------------------------------------------------------------
// Source:    /usr/local/cpanel/base/sharedjs/sqlui.js
// Generated: /usr/local/cpanel/base/sharedjs/sqlui-ko.js
// Module:    legacy_shared/sqlui-ko
// Locale:    ko
// This file is generated by the cpanel localization system
// using the bin/_build_translated_js_hash_files.pl script.
//-------------------------------------------------------------
// !!! Do not hand edit this file !!!
//-------------------------------------------------------------
(function() {
    // The raw lexicon.
    var newLex = {"Close":"닫기","If you change this database’s name, you will be unable to rename it back to “[_1]”. This is because the old name lacks the username prefix ([_2]) that this system requires on the names of all new databases and database users. If you require a name without the prefix, you must contact your server administrator.":"이 데이터베이스의 이름을 변경하면 다시 “[_1]”(으)로 이름을 바꿀 수 없습니다. 이전 이름에 모든 새 데이터베이스와 데이터베이스 사용자에 대해 시스템에서 요구하는 사용자 이름 접두사([_2])가 없기 때문입니다. 접두사가 없는 이름이 필요하다면 서버 관리자에게 연락해야 합니다.","If you change this user’s name, you will be unable to rename it back to “[_1]”. This is because the old name lacks the username prefix ([_2]) that this system requires on the names of all new databases and database users. If you require a name without the prefix, you must contact your server administrator.":"이 사용자의 이름을 변경하면 다시 “[_1]”(으)로 이름을 바꿀 수 없습니다. 이전 이름에 모든 새 데이터베이스와 데이터베이스 사용자에 대해 시스템에서 요구하는 사용자 이름 접두사([_2])가 없기 때문입니다. 접두사가 없는 이름이 필요하다면 서버 관리자에게 연락해야 합니다.","It is a potentially dangerous operation to rename a database. You may want to [output,url,_1,back up this database] before renaming it.":"It is a potentially dangerous operation to rename a database. You may want to [output,url,_1,back up this database] before renaming it.","Rename Database":"데이터베이스 이름 바꾸기","Rename Database User":"데이터베이스 사용자 이름 바꾸기","Renaming database user …":"데이터베이스 사용자 이름을 바꾸는 중…","Renaming database …":"데이터베이스 이름을 바꾸는 중…","Success! The browser is now redirecting …":"성공! 현재 브라우저가 리디렉션되는 중…","Success! This page will now reload.":"성공! 이 페이지가 다시 로딩됩니다.","The new name must be different from the old name.":"새로운 이름은 기존 이름과는 달라야 합니다."};

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
