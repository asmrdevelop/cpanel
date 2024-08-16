package Cpanel::FtpUtils::Proftpd::Kill;

# cpanel - Cpanel/FtpUtils/Proftpd/Kill.pm         Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use strict;
use warnings;

use Cpanel::Validate::Domain::Tiny             ();
use Cpanel::FtpUtils::Config::Proftpd::CfgFile ();
use Cpanel::Transaction::File::Raw             ();

=pod

=head1 NAME

Cpanel::FtpUtils::Proftpd::Kill

=head1 SYNOPSIS

  my $removed = Cpanel::FtpUtils::Proftpd::Kill::remove_servername_from_conf('bob.org');
  if ($removed) {
    print "The vhost 'bob.org' was removed from the proftpd config.\n";
  } else {
    print "The vhost 'bob.org' could not be found in the proftpd config.\n";
  }

=head2 remove_servername_from_conf( SERVERNAME )

Remove a Virtual Host from proftpd.conf

=head3 Arguments

SERVERNAME - The servername to remove from proftpd.conf

=head3 Return Value

  1 - The servername was found and removed
  0 - The servername could not be found

=cut

# NOTE: This is a limited relocation of scripts/killpvhost
# The code was relocated here and the warnings were fixed
#
# remove_servername_from_conf takes the $servername
# of the virtualhost to remove from proftpd.conf
#
sub remove_servername_from_conf {
    my ($servername) = @_;
    my $proftpdconf = Cpanel::FtpUtils::Config::Proftpd::CfgFile::bare_find_conf_file();
    return 0 if !-e $proftpdconf;

    if ( !Cpanel::Validate::Domain::Tiny::validdomainname($servername) ) {
        die "“$servername” is an invalid domain.";
    }

    my $trans_obj              = Cpanel::Transaction::File::Raw->new( path => $proftpdconf );
    my @TFTPCONF               = split( m{\n}, ${ $trans_obj->get_data() } );
    my $keep_this_virtual_host = 1;
    my $inside_virtual_host    = 0;
    my $virtual_host_text;
    my $found_virtual_host_to_remove = 0;
    my $new_conf                     = '';
    foreach my $line (@TFTPCONF) {

        if ($inside_virtual_host) {
            $virtual_host_text = $virtual_host_text . $line . "\n";
            if ( $line =~ /^[ \t]*servername[\s\t]+(ftp\.)?\Q${servername}\E$/i ) {
                $found_virtual_host_to_remove = 1;
                $keep_this_virtual_host       = 0;
            }
            elsif ( $line =~ /^[ \t]*<\/virtualhost/i ) {
                $inside_virtual_host = 0;
                if ($keep_this_virtual_host) { $new_conf .= $virtual_host_text; }
                $virtual_host_text = '';
            }
        }
        elsif ( $line =~ /^[ \t]*<virtualhost/i ) {
            $inside_virtual_host    = 1;
            $keep_this_virtual_host = 1;
            $virtual_host_text      = $line . "\n";
        }
        else {
            $new_conf .= "$line\n";
        }
    }
    $trans_obj->set_data( \$new_conf );
    $trans_obj->save_and_close_or_die();

    return $found_virtual_host_to_remove;
}

1;
