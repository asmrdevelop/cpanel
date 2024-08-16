/* Homeloader - PECL extension which alters the PHP include path for user
 * cpanel - /usr/local/cpanel/src/userphp/homeloader.c
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

#include <unistd.h>
#include <sys/stat.h>
#include <sys/types.h>
#include <pwd.h>
#include <string.h>

#ifdef HAVE_CONFIG_H
#include "config.h"
#endif

#include "php.h"
#include "php_ini.h"
#include "php_homeloader.h"

ZEND_DECLARE_MODULE_GLOBALS(homeloader)

static zend_function_entry homeloader_functions[] = {
  {NULL, NULL, NULL}
};

char *
getpwuid_homedir (uid_t uid)
{
  struct passwd *user_info = getpwuid (uid);
  if (!user_info)
    {
      printf ("pwnam: error getting uid for uid: %d\n", uid);
      exit (1);
    }
  return user_info->pw_dir;
}

static void
php_homeloader_init_globals(zend_homeloader_globals *homeloader_globals)
{
  char *homedir;
  char phpdir[4096];

  homedir = getpwuid_homedir (getuid ());
  snprintf (phpdir, 4096, "%s/php", homedir);

  homeloader_globals->home_php_dir = pestrdup (phpdir, 1);
}

/* check that dirname exists and is a directory */
int
direxists (char *dirname)
{
  struct stat file_stats;

  if (stat (dirname, &file_stats) == -1 || !S_ISDIR (file_stats.st_mode))
    return 0;

  return 1;
}

PHP_MINIT_FUNCTION (homeloader)
{
  ZEND_INIT_MODULE_GLOBALS(homeloader, php_homeloader_init_globals, NULL);

  /* Return failure if we did not allocate and set the home php directory */
  return ( ( HOMELOADER_G(home_php_dir) ) ? SUCCESS : FAILURE );
}

PHP_MSHUTDOWN_FUNCTION (homeloader)
{
  if (HOMELOADER_G(home_php_dir)) {
    pefree(HOMELOADER_G(home_php_dir), 1);
  }

  return SUCCESS;
}

PHP_RINIT_FUNCTION (homeloader)
{
  char new_value[4096];

  if (!direxists (HOMELOADER_G(home_php_dir)))
    {
      return SUCCESS;
    }

  snprintf (new_value, 4096, "%s:%s", INI_STR("include_path"), HOMELOADER_G(home_php_dir));

  if (zend_alter_ini_entry
      ("include_path", strlen ("include_path") + 1, new_value,
       strlen (new_value), PHP_INI_USER, PHP_INI_STAGE_RUNTIME) == FAILURE)
    {
      return FAILURE;
    }
  return SUCCESS;
}

PHP_MINFO_FUNCTION(homeloader) {
    php_info_print_table_start( );
    php_info_print_table_header(2, "homeloader support", "enabled");
    php_info_print_table_end( );
}

zend_module_entry homeloader_module_entry = {
#if ZEND_MODULE_API_NO >= 20010901
  STANDARD_MODULE_HEADER,
#endif
  PHP_HOMELOADER_EXTNAME,
  homeloader_functions,
  PHP_MINIT (homeloader),
  PHP_MSHUTDOWN (homeloader),
  PHP_RINIT (homeloader),
  NULL,
  PHP_MINFO (homeloader),
#if ZEND_MODULE_API_NO >= 20010901
  PHP_HOMELOADER_VERSION,
#endif
  STANDARD_MODULE_PROPERTIES
};

#ifdef COMPILE_DL_HOMELOADER
ZEND_GET_MODULE (homeloader)
#endif
