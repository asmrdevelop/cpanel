//~~GENERATED~~
//-------------------------------------------------------------
// Source:    /usr/local/cpanel/base/sharedjs/sslwidgets.js
// Generated: /usr/local/cpanel/base/sharedjs/sslwidgets-zh.js
// Module:    legacy_shared/sslwidgets-zh
// Locale:    zh
// This file is generated by the cpanel localization system
// using the bin/_build_translated_js_hash_files.pl script.
//-------------------------------------------------------------
// !!! Do not hand edit this file !!!
//-------------------------------------------------------------
(function() {
    // The raw lexicon.
    var newLex = {"Certificate Expiration":"证书过期","Certificate Key Sizes":"证书密钥大小","Contact your certificate authority ([_1]) to reissue this certificate with a [numf,_2]-bit key.":"请联系您的证书颁发机构([_1])，请求其使用 [numf,_2] 位密钥重新颁发该证书。","Contact your certificate authority to reissue this certificate with a longer key.":"联系您的证书颁发机构，要求其使用较长密钥重新颁发该证书。","Generate and install a new self-signed certificate immediately. Then, replace this certificate with a certificate signed by a valid certificate authority as soon as possible.":"立即生成并安装新的自签名证书。 然后，尽快使用有效证书颁发机构签名的证书替换此证书。","It is highly recommended that you do not install this certificate.":"强烈建议您不要安装此证书。","Purchase a new certificate.":"Purchase a new certificate.","Self-Signed Certificates":"自签名证书","The recommended key size for a certificate is currently [quant,_1,bit,bits].":"目前推荐使用的证书密钥大小为 [quant,_1,位,位]。","This certificate will expire in [quant,_1,day,days].":"此证书将于 [quant,_1,天,天] 后过期。","This certificate’s key is too short ([quant,_1,bit,bits]). This key will not protect against a spoofing attack.":"该证书的密钥太短([quant,_1,位,位])。 该密钥不能防止电子欺骗的攻击。","You should generate another self-signed certificate for [quant,_1,this domain,these domains] with a [numf,_2]-bit key.":"您需要使用 [numf,_2] 位密钥为 [quant,_1,个此域,个这些域]生成一个新的自签名证书。","You should request a replacement certificate from the issuer ([_1]) as soon as possible.":"您应尽快从颁发者([_1])那里请求替换证书。"};

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
