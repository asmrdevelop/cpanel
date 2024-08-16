## no critic (RequireFilenameMatchesPackage)

# cpanel - install/FixGreylistingPerms.pm          Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

package Install::FixGreylistingPerms;
## use critic

use base qw( Cpanel::Task );

use strict;
use warnings;

use Cpanel::GreyList::Config ();
use Cpanel::FileUtils::Chown ();

our $VERSION = '1.0';

=head1 DESCRIPTION

    Adjust owner and permission of greylist configuration
    file and sqlite database.

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

    $self->set_internal_name('fix_greylisting_perms');

    return $self;
}

sub _fix_perms_on_conf_and_db {

    my $conf_file = Cpanel::GreyList::Config::get_conf_file();
    my $db_file   = Cpanel::GreyList::Config::get_sqlite_db();

    foreach my $file ( $conf_file, $db_file ) {
        Cpanel::FileUtils::Chown::check_and_fix_owner_and_permissions_for(
            'uid'         => 0,
            'gid'         => 0,
            'octal_perms' => 0600,
            'path'        => $file,
            'create'      => 0,
        );
    }

    return 1;
}

sub perform {
    my $self = shift;
    return _fix_perms_on_conf_and_db();
}

1;

__END__
