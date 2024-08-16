/*
  cpanel - src/userruby/ruby-wrapper.c             Copyright 2022 cPanel, L.L.C.
                                                            All rights reserved.
  copyright@cpanel.net                                         http://cpanel.net
  This code is subject to the cPanel license. Unauthorized copying is prohibited
*/

#include <unistd.h>
#include <sys/stat.h>
#include <sys/types.h>
#include <pwd.h>
#include <string.h>
#include <stdlib.h>

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


/* check that dirname exists and is a directory */
int
direxists (char *dirname)
{
  struct stat file_stats;

  if (stat (dirname, &file_stats) == -1 || !S_ISDIR (file_stats.st_mode))
    return 0;

  return 1;
}


int
main (int argc, char *argv[])
{
  char *version = "cPanel Ruby Wrapper 1.1";
  uid_t uid = getuid ();
  char *cmd[argc + 2];
  int i = 0;
  char rubydir[4096];
  char gemdir[4096];
  char *homedir;

  if (uid == 0)
    {
      execv ("/usr/bin/ruby-bin", argv);
    }

  homedir = getpwuid_homedir (uid);
  snprintf (rubydir, 4096, "%s/ruby", homedir);
  if (!direxists (rubydir))
    {
      execv ("/usr/bin/ruby-bin", argv);
    }
  snprintf (gemdir, 4096, "%s/gems", rubydir);
  setenv ("GEM_PATH", gemdir, 0);

  cmd[0] = argv[0];
  cmd[1] = "-I";
  cmd[2] = rubydir;
  for (i = 1; i < argc; i++)
    {
      cmd[i + 2] = argv[i];
    }
  cmd[argc + 2] = NULL;
  execv ("/usr/bin/ruby-bin", cmd);
}
