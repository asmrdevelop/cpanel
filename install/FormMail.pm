package Install::FormMail;

# cpanel - install/FormMail.pm                     Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use base qw( Cpanel::Task );

use strict;
use warnings;
use Cwd                     ();
use Cpanel::FileUtils::Link ();

our $VERSION = '1.0';

=head1 DESCRIPTION

    Create symlinks to universal-redirect.cgi and autoconfig.cgi

=over 1

=item Type: Sanity

=item Frequency: always

=item EOL: never

=back

=cut

exit __PACKAGE__->runtask() unless caller;

sub new {
    my $proto = shift;
    my $self  = $proto->SUPER::new;

    $self->set_internal_name('formmail');

    return $self;
}

sub _make_links {
    my $target_dir        = shift;
    my $real_file         = shift;
    my $files_to_link_ref = shift;

    my $owd = Cwd::cwd();

    chdir $target_dir;
    foreach my $file (@$files_to_link_ref) {
        if ( !Cpanel::FileUtils::Link::safeunlink($file) ) {
            warn "Failed to unlink $file";
        }
        if ( !Cpanel::FileUtils::Link::safelink( $real_file, $file ) ) {
            warn "Failed to link $file to $real_file";
        }
    }

    chdir $owd;

    return 1;
}

sub perform {
    my $self = shift;

    my $target_dir = '/usr/local/cpanel/cgi-sys';
    my $real_file  = 'universal-redirect.cgi';
    if ( -e "$target_dir/$real_file" ) {
        _make_links( $target_dir, $real_file, [ 'sredirect.cgi', 'swhmredirect.cgi', 'whmredirect.cgi', 'wredirect.cgi', 'redirect.cgi' ] );
    }
    else {
        warn "$real_file does not exist to be linked to";
        return;
    }

    $real_file = 'autoconfig.cgi';
    if ( -e "$target_dir/$real_file" ) {
        _make_links( $target_dir, $real_file, ['autodiscover.cgi'] );
    }
    else {
        warn "$real_file does not exist to be linked to";
        return;
    }

    return 1;
}

1;

__END__
