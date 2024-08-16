<?php
/**
 * cpanel - /usr/local/cpanel/php/WHM.php         Copyright(c) 2020 cPanel, L.L.C.
 *                                                          All rights reserved.
 * copyright@cpanel.net                                        http://cpanel.net
 */

class WHM{
    public static function header($pageTitle = "WHM Plugin", $skipSupport = NULL, $skipHeader = NULL, $cspNonce = NULL){
        $headerStr = self::processHeader($pageTitle, $skipSupport, $skipHeader, $cspNonce);
        if($headerStr){
            echo($headerStr);
        }
    }
    public static function getHeaderString($pageTitle = "WHM Plugin", $skipSupport = NULL, $skipHeader = NULL, $cspNonce = NULL){
        $headerStr = self::processHeader($pageTitle, $skipSupport, $skipHeader, $cspNonce);
        if($headerStr){
            return $headerStr;
        }
    }
    public static function footer(){
        $cacheDir = self::getCacheDir();
        require_once($cacheDir."/_generated_footer_files/footer.html");
    }
    public static function getFooterString(){
        $cacheDir = self::getCacheDir();
        $footerStr = file_get_contents($cacheDir."/_generated_footer_files/footer.html");
        return $footerStr;
    }

    private static function processHeader($pageTitle, $skipSupport, $skipHeader, $cspNonce = NULL){
        $skipSupport = self::setArg($skipSupport);
        $skipHeader = self::setArg($skipHeader);

        $user = getenv("REMOTE_USER");
        $cpSession = getenv('cp_security_token');
        $cacheKey = "";
        $cacheDir = self::getCacheDir();

        //Error checking and string replacement
        if(!$cpSession){
            //A user has the abiility to run without a session token.
            $cpSession = "";
        }
        if(isset($user)){
            //Get user's cache key for JSON file, based on user's name.
            $cacheKey = self::getUserCacheKey($user);

            //Load and Process selected header.
            $headerStr = self::loadFileToStr($cacheDir."/_generated_header_files/".$cacheKey."_".$skipSupport."_".$skipHeader.".html");
            $headerStr = self::processHeaderStrings($headerStr, $cpSession, $user, $pageTitle, $cspNonce);

            return $headerStr;
        }else{
            throw new Exception("REMOTE_USER does not exist.");
            return false;
        }
    }
    private static function getUserCacheKey($user){
        $cacheDir = self::getCacheDir();
        $cacheFile = file_get_contents($cacheDir."/_generated_header_files/cache_keys.json");
        $cacheObj = json_decode($cacheFile);
        if(isset($cacheObj->$user)){
            return $cacheObj->$user;
        }else{
            throw new Exception("User does not exist in cache_keys. Try regenerating the cache.");
        }
        return "";
    }
    private static function loadFileToStr($headerFile){
        $headerFile = file_get_contents($headerFile);
        return $headerFile;
    }
    private static function getCacheDir(){
        $cacheDirectory = getenv("whm_chrome_cache_directory");
        if(!$cacheDirectory){
            //Use system cache directory if not set
            $cacheDirectory = "/var/cpanel/caches";
        }
        return $cacheDirectory;
    }
    private static function processHeaderStrings($fileStr, $token, $user, $title, $cspNonce = NULL){
        $fileStr = str_replace('/cpsess0000000000', $token, $fileStr);//All session links
        $fileStr = str_replace('cpuser00000000000', $user, $fileStr);//All user references
        $fileStr = str_replace('Results of Your Request', $title, $fileStr);//Set page title
        $nonce_replacement = '';
        if ( isset($cspNonce) ) {
            $fileStr = str_replace('nonce="00000000000"','nonce="'.$cspNonce.'"', $fileStr);
        } else {
            $fileStr = str_replace('nonce="00000000000"','', $fileStr);
        }
        return $fileStr;
    }
    private static function setArg($arg){
        if(isset($arg)){
            if($arg === false || $arg === 0){
                return 0;
            }else{
                return 1;
            }
        }else{
            return 0;
        }
    }
}
?>