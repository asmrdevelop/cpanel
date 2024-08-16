package Cpanel::Admin::Modules::Cpanel::file_protect;

# cpanel - Cpanel/Admin/Modules/Cpanel/file_protect.pm
#                                                  Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use cPstrict;

use parent qw( Cpanel::Admin::Base );

use Cpanel::FileProtect::Sync ();
use Cpanel::Locale            ();
use Cpanel::Exception         ();
use Cpanel::PwCache           ();

=head1 MODULE

C<Cpanel::Admin::Modules::Cpanel::file_protect>

=head1 DESCRIPTION

C<Cpanel::Admin::Modules::Cpanel::file_protect> provides a way for the FileProtect rules
to be applied to a folder in the users directory.

=head1 SYNOPSIS

  use Cpanel::AdminBin::Call ();

  my $dir = '/home/user/public_html';

  Cpanel::AdminBin::Call::call(
      'Cpanel',
      'file_protect',
      'PROTECT_DIRECTORY',
      $dir
  );

=head1 FUNCTIONS

=cut

my $locale;

sub _locale {
    return $locale ||= Cpanel::Locale->get_handle();
}

use constant _actions => (qw(PROTECT_DIRECTORY));

sub _user_error ($msg) {
    return Cpanel::Exception::create( 'AdminError', [ message => $msg ] );
}

=head2 INSTANCE->PROTECT_DIRECTORY(DIRECTORY)

Apply the FileProtect rules to the provided directory.

=head3 ARGUMENTS

=over

=item DIRECTORY - string

The directory to apply protection rules too.

=back

=cut

sub PROTECT_DIRECTORY {
    my ( $self, $directory ) = @_;
    $directory //= q<>;
    $directory =~ s{/+}{/};    # remove consecutive //

    if ( !$directory ) {
        die _user_error( _locale()->maketext("You must provide a value for the directory parameter.") );
    }

    my $user    = $self->get_caller_username();
    my $homedir = Cpanel::PwCache::gethomedir($user);

    if ( $directory ne $homedir && $directory !~ m{^\Q$homedir\E/} ) {
        die _user_error( _locale()->maketext( "The provided “[_1]” directory does not reside in the user’s home directory, the “[_2]” directory.", $directory, $homedir ) );
    }

    Cpanel::FileProtect::Sync::protect_web_directory( $user, $directory );
    return;
}

1;
