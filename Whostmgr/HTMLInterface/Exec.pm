package Whostmgr::HTMLInterface::Exec;

# cpanel - Whostmgr/HTMLInterface/Exec.pm          Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use IPC::Open3;

use Cpanel::Template::Interactive ();

sub htmlexec {
    my (@CMD) = @_;

    #    chdir '/usr/local/cpanel/whostmgr/libexec' or die "Failed to chdir: $!";
    #    my $command_output = Cpanel::SafeRun::Errors::saferunallerrors(@CMD);

    my $fh;
    if ( my $pid = IPC::Open3::open3( undef, $fh, $fh, @CMD ) ) {
        Cpanel::Template::Interactive::process_template(
            'whostmgr',
            {
                'template_file' => 'htmlexec.tmpl',
                'data'          => { 'fh' => $fh, },
            }
        );

        close $fh;
        waitpid $pid, 0;
    }

    #    Whostmgr::HTMLInterface::Output::print2anyoutput($$templated_results);
}

1;
