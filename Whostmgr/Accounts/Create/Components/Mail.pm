package Whostmgr::Accounts::Create::Components::Mail;

# cpanel - Whostmgr/Accounts/Create/Components/Mail.pm
#                                                  Copyright 2024 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

=head1 NAME

Whostmgr::Accounts::Create::Components::Mail

=head1 SYNOPSIS

    use 'Whostmgr::Accounts::Create::Components::Mail';
    ...

=head1 DESCRIPTION

Sets up the valiases/vdomainaliases/vfilters files for the new user.

NOTE: Keep the directory permissions and setup logic in sync with
Cpanel::Email::Perms::System.

=cut

use cPstrict;

use parent 'Whostmgr::Accounts::Create::Components::Base';

use constant pretty_name => "Mail";

use Cpanel::Email::Constants ();
use Cpanel::MailTools        ();
use Cpanel::PwCache          ();
use IO::SigGuard             ();

use Cpanel::Imports;

sub _run ( $output, $user = {} ) {

    my @maildirs = (
        [ valiases       => $Cpanel::ConfigFiles::VALIASES_DIR ],
        [ vdomainaliases => $Cpanel::ConfigFiles::VDOMAINALIASES_DIR ],
        [ vfilters       => $Cpanel::ConfigFiles::VFILTERS_DIR ],
    );

    my $mailgid = ( Cpanel::PwCache::getpwnam_noshadow('mail') )[3];

    foreach my $item (@maildirs) {
        my ( $label, $maildir ) = @$item;

        # Ignore error in case it exists. Previously we'd check if it exists
        # which wasn't even necessary since we did no error checking.
        mkdir( $maildir, Cpanel::Email::Constants::VDIR_PERMS() );

        my $path = "$maildir/$user->{'domain'}";

        #Blow away any file that might already be there.
        open my $fh, '>', $path or do {
            logger()->warn("open(>>, $path): $!");
            next;
        };

        #This file needs specific content on initialization.
        if ( $maildir eq $Cpanel::ConfigFiles::VALIASES_DIR ) {
            my $default_mail_dest = Cpanel::MailTools::getdefaultmailaction( $user->{'user'} );

            IO::SigGuard::syswrite( $fh, "*: $default_mail_dest\n" ) or do {
                logger()->warn("write($path): $!");
            };
        }

        chmod( Cpanel::Email::Constants::VFILE_PERMS(), $fh ) or do {
            logger()->warn("chmod($path): $!");
        };

        chown( $user->{'uid'}, $mailgid, $fh ) or do {
            logger()->warn("chown($user->{'uid'}, $mailgid, $path): $!");
        };

        $$output .= "$label ...";
    }

    return 1;
}

1;
