package Install::PostMasterAlias;

# cpanel - install/PostMasterAlias.pm              Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use cPstrict;

use base qw( Cpanel::Task );

use Cpanel::Transaction::File::Raw ();
use Cpanel::FileUtils::Chown       ();

our $VERSION = '1.0';

our $ALIASES_FILE = q{/etc/aliases};

=head1 DESCRIPTION

    Add postmatser alias to /etc/aliases if missing.

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

    $self->set_internal_name('postmasteralias');

    return $self;
}

sub perform ($self) {

    Cpanel::FileUtils::Chown::check_and_fix_owner_and_permissions_for(
        'uid'         => 0,
        'gid'         => 0,
        'octal_perms' => 0644,
        'path'        => $ALIASES_FILE,
    );

    add_if_needed('postmaster');
    add_if_needed('nobody');

    return 1;
}

sub add_if_needed ($user) {

    return if _file_has_user($user);
    return _add_to_file( $ALIASES_FILE, 0644, qq{$user: root\n} );
}

sub _file_has_user ($user) {

    if ( open( my $fh, '<', $ALIASES_FILE ) ) {
        while ( my $line = readline($fh) ) {
            return 1 if $line =~ m{^\s*\Q$user\E:};
        }
    }

    return;
}

sub _add_to_file ( $file, $perms, $line ) {

    my $group_trans = Cpanel::Transaction::File::Raw->new( 'path' => $file, 'permissions' => $perms );
    my $dataref     = $group_trans->get_data() // '';
    $$dataref .= "\n" if length $$dataref && substr( $$dataref, -1, 1 ) ne "\n";
    $$dataref .= $line;
    $$dataref .= "\n" if substr( $line, -1, 1 ) ne "\n";
    $group_trans->save_and_close_or_die();

    return 1;
}

1;
