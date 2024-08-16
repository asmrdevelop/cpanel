package Cpanel::Kill::OpenFiles;

# cpanel - Cpanel/Kill/OpenFiles.pm                Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use cPstrict;

use Cpanel::Kill::Single ();
use Cpanel::Lsof         ();

# safekill_procs_access_files_under_dir is expceted to be used
# to kill processes that would prevent a rename() from being successful
#
# For example if something has /home/bob open
# and you call
# rename("/home/bob","/home/bob2") if may fail with
# Device or Resource Busy.
#
# Calling safekill_procs_access_files_under_dir("/home/bob") should
# make this successful
#
sub safekill_procs_access_files_under_dir {
    my ($dir) = @_;

    foreach my $pid ( _get_pids_to_kill($dir) ) {
        if ( $pid < 5 ) { die "BUG: safekill_procs_access_files_under_dir tried to kill a pid less then 5"; }
        Cpanel::Kill::Single::safekill_single_pid( $pid, 1 );
    }

    return 1;
}

sub _get_pids_to_kill {
    my ($dir) = @_;

    $dir =~ s{/+}{/}g;    #collapse slashes
                          # NOTE for reviewer: I *think* what the chdir was doing here earlier was
                          # ensuring that when the filesystem *is* an overlay, lsof would simply
                          # execute *with no dir* passed in. In this case the default behavior was
                          # to impute no dir as "just get it for cwd lol" which in the previous case
                          # was actually '/' due to the chdir. Oddly, we normally would die because
                          # of this, in the transliteration call below... had we actually passed in
                          # what we were going to run lsof with. But we don't, so the way it was
                          # actually dealing with this was just to iterate over every pid on the
                          # system via lsof output and parse the outcome in that case, which somewhat
                          # defeats the purpose of calling lsof in the first place versus walking
                          # /proc yourself. Thus I don't really get what the original above comment
                          # was on about, as we *always* were taking "the expensive route" as far
                          # as I can tell, regardless of whether the FS was an overlay or not,
                          # as in the case that we were not an overlayfs, $source_mount_point is undef
                          # anyways, leading to us *always* just doing lsof on '/'!
                          #
                          # Anyways, we're not "missing" anything as far as I can tell over in
                          # Cpanel::Lsof just due to "one weird trick" I'm doing in
                          # `lsof_formatted_pids` -- only do a partial match on file.
                          # So long as the file "starts with" the path, you are good to go.
                          # This is in fact what was the actual desired behavior per the tests,
                          # and as such what I made lsof_formatted_pids output. Not sure if that
                          # name is thus the best choice anymore.
                          #
                          # NOTE for testers: How does this all work out now that we're not checking
                          # on the overlayfs stuff when we are indeed on an overlay file system?
                          # It's not like we ever tested this in unit tests. Also, how exactly does
                          # this work when chroots are involved for pids? I don't think we ever
                          # actually accounted for this.

    if ( ( $dir =~ tr{/}{} ) < 2 ) {
        die "safekill_procs_access_files_under_dir cannot kill processes under a top level directory";
    }

    return Cpanel::Lsof::lsof_formatted_pids($dir)->@*;
}

1;
