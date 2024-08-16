package Cpanel::Template::Ftp;

# cpanel - Cpanel/Template/Ftp.pm                  Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use cPstrict;

use Cpanel::Debug    ();
use Cpanel::LoadFile ();
use Cpanel::OS       ();

=head1 NAME

Cpanel::Template::Ftp

=head1 DESCRIPTION

Cpanel::Template::Ftp is used to setup the stdvhost and stdvhostnonano
files when using proftpd.

=head1 SYNOPSIS

    my $content = Cpanel::Template::Ftp::getftptemplate(
        'stdvhostnoanon', 'proftpd',
        $domain, $newip, $user, $user_homedir
    );

=cut

=head1 METHODS

=head2 getftptemplate( $template, $daemon, $domain, $ip, $user, $homedir )

Returns a string with the interpolated template for '$template' for the ftp server '$daemon'.
The variables '$domain, $ip, $user, $homedir' are used for the template.

=cut

sub getftptemplate ( $template, $daemon, $domain, $ip, $user, $homedir ) {    ## no critic qw(Subroutines::ProhibitManyArgs)

    my $templatefile = '/usr/local/cpanel/etc/ftptemplates/' . $daemon . '/' . $template;
    if ( !-e $templatefile ) {
        Cpanel::Debug::log_warn("Unable to locate template file $templatefile");
        return;
    }

    my $output = Cpanel::LoadFile::load($templatefile);
    if ( !$output ) {
        Cpanel::Debug::log_warn("Unable to read template file $templatefile: $!");
        return;
    }

    my %FILL = (
        'domain'  => $domain,
        'ip'      => $ip,
        'user'    => $user,
        'homedir' => $homedir,
        'sudoers' => Cpanel::OS::sudoers(),
    );

    $output =~ s/%(domain|ip|user|homedir|sudoers)%/$FILL{$1}/g;

    return $output;
}

1;
