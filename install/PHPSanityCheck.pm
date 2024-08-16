package Install::PHPSanityCheck;

# cpanel - install/PHPSanityCheck.pm               Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use base qw( Cpanel::Task );

use strict;
use warnings;

use Cpanel::ServerTasks     ();
use Cpanel::Binaries        ();
use Cpanel::FileUtils::Link ();
use Cpanel::SafeDir::MK     ();
use Whostmgr::API::1::Lang::PHP

  our $VERSION = '1.2';

=head1 DESCRIPTION

    Check PHP ini file and install custom 3rd party php.ini files.

=over 1

=item Type: Fresh Install, Sanity

=item Frequency: always

=item EOL: never

=back

=cut

exit __PACKAGE__->runtask() unless caller;

sub new {
    my $proto = shift;
    my $self  = $proto->SUPER::new;

    $self->set_internal_name('phpsanitycheck');
    $self->add_dependencies(qw( taskqueue ));

    return $self;
}

sub perform {
    my $self = shift;

    my $phpini = '/usr/local/cpanel/3rdparty/lib/php.ini';

    if ( -e $phpini ) {
        if ( !Cpanel::FileUtils::Link::safeunlink($phpini) ) {
            warn 'Failed to unlink PHP ini file';
        }
    }

    local $@;
    eval { Cpanel::ServerTasks::schedule_task( ['PHPTasks'], 1, 'checkphpini_and_install_php_inis' ); 1; };
    warn if $@;

    my $php_prefix = Cpanel::Binaries::get_prefix('php');

    # bin/install_php_inis creates directories; keys of %symlinks
    my %symlinks = (

        $php_prefix . "/etc/php.ini"            => "/usr/local/cpanel/3rdparty/etc/php.ini",
        $php_prefix . "/etc/phpmyadmin/php.ini" => "/usr/local/cpanel/3rdparty/etc/phpmyadmin/php.ini",
        $php_prefix . "/etc/phppgadmin/php.ini" => "/usr/local/cpanel/3rdparty/etc/phppgadmin/php.ini",
        $php_prefix . "/etc/roundcube/php.ini"  => "/usr/local/cpanel/3rdparty/etc/roundcube/php.ini",
    );

    foreach my $link ( keys %symlinks ) {
        unless ( -l $symlinks{$link} && ( readlink( $symlinks{$link} ) eq $link ) ) {

            # Make sure the diff app directories exist in /usr/local/cpanel/3rdparty/etc
            my $dir = $symlinks{$link};
            $dir =~ s/\/php.ini$//g;

            if ( !-d $dir ) {
                Cpanel::SafeDir::MK::safemkdir( $dir, '0755' );
            }

            if ( -d $symlinks{$link} ) {
                warn "Unable to create symlink $symlinks{$link} because this is currently a directory.";
                next;
            }
            elsif ( -e $symlinks{$link} && !-l $symlinks{$link} ) {
                warn "File $symlinks{$link} is being replaced with a symlink to $link.";
            }

            if ( !Cpanel::FileUtils::Link::safeunlink( $symlinks{$link} ) ) {
                warn "Failed to unlink $symlinks{$link}: $!";
            }
            symlink( $link, $symlinks{$link} ) or warn "Unable to create symlink $symlinks{$link}: $!";
        }
    }

    return 1;
}

1;

__END__
