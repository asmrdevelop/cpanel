<?php
// +-----------------------------------------------------------------------+
// | Copyright (c) 2002-2003 Richard Heyes                                 |
// | All rights reserved.                                                  |
// |                                                                       |
// | Redistribution and use in source and binary forms, with or without    |
// | modification, are permitted provided that the following conditions    |
// | are met:                                                              |
// |                                                                       |
// | o Redistributions of source code must retain the above copyright      |
// |   notice, this list of conditions and the following disclaimer.       |
// | o Redistributions in binary form must reproduce the above copyright   |
// |   notice, this list of conditions and the following disclaimer in the |
// |   documentation and/or other materials provided with the distribution.|
// | o The names of the authors may not be used to endorse or promote      |
// |   products derived from this software without specific prior written  |
// |   permission.                                                         |
// |                                                                       |
// | THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND CONTRIBUTORS   |
// | "AS IS" AND ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT     |
// | LIMITED TO, THE IMPLIED WARRANTIES OF MERCHANTABILITY AND FITNESS FOR |
// | A PARTICULAR PURPOSE ARE DISCLAIMED. IN NO EVENT SHALL THE COPYRIGHT  |
// | OWNER OR CONTRIBUTORS BE LIABLE FOR ANY DIRECT, INDIRECT, INCIDENTAL, |
// | SPECIAL, EXEMPLARY, OR CONSEQUENTIAL DAMAGES (INCLUDING, BUT NOT      |
// | LIMITED TO, PROCUREMENT OF SUBSTITUTE GOODS OR SERVICES; LOSS OF USE, |
// | DATA, OR PROFITS; OR BUSINESS INTERRUPTION) HOWEVER CAUSED AND ON ANY |
// | THEORY OF LIABILITY, WHETHER IN CONTRACT, STRICT LIABILITY, OR TORT   |
// | (INCLUDING NEGLIGENCE OR OTHERWISE) ARISING IN ANY WAY OUT OF THE USE |
// | OF THIS SOFTWARE, EVEN IF ADVISED OF THE POSSIBILITY OF SUCH DAMAGE.  |
// |                                                                       |
// +-----------------------------------------------------------------------+
// | Author: Richard Heyes <richard@php.net>                               |
// +-----------------------------------------------------------------------+
//
// $Id$

/**
* Client implementation of various SASL mechanisms
*
* @author  Richard Heyes <richard@php.net>
* @access  public
* @version 1.0
* @package Auth_SASL2
*/
class Auth_SASL2
{
    /**
    * Factory class. Returns an object of the request
    * type.
    *
    * @param string $type One of: Anonymous
    *                             Login (DEPRECATED)
    *                             Plain
    *                             External
    *                             CramMD5 (DEPRECATED)
    *                             DigestMD5 (DEPRECATED)
    *                             SCRAM-* (any mechanism of the SCRAM family)
    *                     Types are not case sensitive
    */
    function factory($type)
    {
        switch (strtolower($type)) {
            case 'anonymous':
                $filename  = 'Auth/SASL2/Anonymous.php';
                $classname = 'Auth_SASL2_Anonymous';
                break;

            case 'login':
                /* TODO trigger deprecation warning in 1.0.0 and remove LOGIN authentication in 2.0.0
                trigger_error(__CLASS__ . ': Authentication method LOGIN' .
                    ' is no longer secure and should be avoided.', E_USER_DEPRECATED);
                */
                $filename  = 'Auth/SASL2/Login.php';
                $classname = 'Auth_SASL2_Login';
                break;

            case 'plain':
                $filename  = 'Auth/SASL2/Plain.php';
                $classname = 'Auth_SASL2_Plain';
                break;

            case 'external':
                $filename  = 'Auth/SASL2/External.php';
                $classname = 'Auth_SASL2_External';
                break;

            case 'crammd5':
                // $msg = 'Deprecated mechanism name. Use IANA-registered name: CRAM-MD5.';
                // trigger_error($msg, E_USER_DEPRECATED);
            case 'cram-md5':
                /* TODO trigger deprecation warning in 1.0.0 and remove CRAM-MD5 authentication in 2.0.0
                trigger_error(__CLASS__ . ': Authentication method CRAM-MD5' .
                    ' is no longer secure and should be avoided.', E_USER_DEPRECATED);
                */
                $filename  = 'Auth/SASL2/CramMD5.php';
                $classname = 'Auth_SASL2_CramMD5';
                break;

            case 'digestmd5':
                // $msg = 'Deprecated mechanism name. Use IANA-registered name: DIGEST-MD5.';
                // trigger_error($msg, E_USER_DEPRECATED);
            case 'digest-md5':
                /* TODO trigger deprecation warning in 1.0.0 and remove DIGEST-MD5 authentication in 2.0.0
                trigger_error(__CLASS__ . ': Authentication method DIGEST-MD5' .
                    ' is no longer secure and should be avoided.', E_USER_DEPRECATED);
                */
                $filename  = 'Auth/SASL2/DigestMD5.php';
                $classname = 'Auth_SASL2_DigestMD5';
                break;

            default:
                $scram = '/^SCRAM-(.{1,9})$/i';
                if (preg_match($scram, $type, $matches))
                {
                    $hash = $matches[1];
                    $filename = __DIR__ .'/SASL2/SCRAM.php';
                    $classname = 'Auth_SASL2_SCRAM';
                    $parameter = $hash;
                    break;
                }
                throw new InvalidArgumentException('Invalid SASL mechanism type');
                break;
        }

        require_once $filename;
        if (isset($parameter)) {
            $obj = new $classname($parameter);
        } else {
            $obj = new $classname();
        }

        return $obj;
    }
}


