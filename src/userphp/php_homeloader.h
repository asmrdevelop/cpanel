/* Homeloader - PECL extension which alters the PHP include path for user
 * cpanel - /usr/local/cpanel/src/userphp/php_homeloader.h
 *
 * Copyright (c) 2013, cPanel, Inc.
 * All rights reserved.
 * http://cpanel.net
 *
 * Redistribution and use in source and binary forms, with or without
 * modification, are permitted provided that the following conditions are met:
 *
 * 1. Redistributions of source code must retain the above copyright notice,
 * this list of conditions and the following disclaimer.
 *
 * 2. Redistributions in binary form must reproduce the above copyright notice,
 * this list of conditions and the following disclaimer in the documentation
 * and/or other materials provided with the distribution.
 *
 * 3. Neither the name of the owner nor the names of its contributors may be
 * used to endorse or promote products derived from this software without
 * specific prior written permission.
 *
 * THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND CONTRIBUTORS "AS IS" AND
 * ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE IMPLIED
 * WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE ARE
 * DISCLAIMED. IN NO EVENT SHALL THE COPYRIGHT HOLDER OR CONTRIBUTORS BE LIABLE
 * FOR ANY DIRECT, INDIRECT, INCIDENTAL, SPECIAL, EXEMPLARY, OR CONSEQUENTIAL
 * DAMAGES (INCLUDING, BUT NOT LIMITED TO, PROCUREMENT OF SUBSTITUTE GOODS OR
 * SERVICES; LOSS OF USE, DATA, OR PROFITS; OR BUSINESS INTERRUPTION) HOWEVER
 * CAUSED AND ON ANY THEORY OF LIABILITY, WHETHER IN CONTRACT, STRICT LIABILITY,
 * OR TORT (INCLUDING NEGLIGENCE OR OTHERWISE) ARISING IN ANY WAY OUT OF THE USE
 * OF THIS SOFTWARE, EVEN IF ADVISED OF THE POSSIBILITY OF SUCH DAMAGE.
 */

#ifndef PHP_HOMELOADER_H
#define PHP_HOMELOADER_H 1

#ifdef ZTS
#include "TSRM.h"
#endif

ZEND_BEGIN_MODULE_GLOBALS(homeloader)
    char *home_php_dir;
ZEND_END_MODULE_GLOBALS(homeloader)

#ifdef ZTS
#define HOMELOADER_G(v) TSRMG(homeloader_globals_id, zend_homeloader_globals *, v)
#else
#define HOMELOADER_G(v) (homeloader_globals.v)
#endif

#define PHP_HOMELOADER_VERSION "1.1"
#define PHP_HOMELOADER_EXTNAME "homeloader"

extern zend_module_entry homeloader_module_entry;
#define phpext_homeloader_ptr &homeloader_module_entry

PHP_MINIT_FUNCTION(homeloader);
PHP_MSHUTDOWN_FUNCTION(homeloader);
PHP_RINIT_FUNCTION(homeloader);
PHP_MINFO_FUNCTION(homeloader);

#endif
