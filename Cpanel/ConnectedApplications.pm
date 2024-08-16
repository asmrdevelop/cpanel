# cpanel - Cpanel/ConnectedApplications.pm           Copyright 2022 cPanel, L.L.C.
#                                                           All rights Reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

package Cpanel::ConnectedApplications;

use cPstrict;

use Cpanel::Autodie                       ();
use Cpanel::Context                       ();
use Cpanel::Mkdir                         ();
use Cpanel::Transaction::File::JSONReader ();
use Cpanel::Transaction::File::JSON       ();

use constant STORAGE_NAME => 'conn-apps.json';

our $DIR_PERMS  = 0700;
our $FILE_PERMS = 0600;

=head1 MODULE

C<Cpanel::ConnectedApplications>

=head1 DESCRIPTION

C<Cpanel::ConnectedApplications> provides the core implementation for persisting and managing information
about external applications that are linked to this instance of cPanel & WHM.

The underlying storage is a JSON file. The location of the storage file is determined by the caller.

See the API calls that use this storage mechanism to find the storage paths.

See: C<Whostmgr::API::1::ConnectedApplications>

=head1 SYNOPSIS

  use Cpanel::ConnectedApplications ();

  my $reseller = 'user1';
  my $configPath = "/var/cpanel/resellers/$reseller";

  my $apps = Cpanel::ConnectedApplications->new(path => $configPath);

  my $app_data = {
      jwt => { ... },
      token_name => "...",
      public_key => "...",
      ...,
  };

  # Save a newly-linked application's data to the database for the user.
  $apps->save('cp-cloud', $app_data);

  # Remove a previously linked application from the database. No cleanup happens for the resources.
  $apps->remove('bad-app');

  # Fetch the data for just one linked application.
  my $saved_data = $apps->load('cp-cloud');

  # Fetch the data for all the linked applications as an array of applications objects.
  my $list = $apps->list();

=head1 CONSTRUTOR

=cut

sub new ( $class, %args ) {
    my $self = {%args};

    $self->{path} =~ s{/$}{};

    bless $self, $class;
    return $self;
}

=head1 METHODS

=head2 INSTANCE->save(NAME, DATA)

=head3 ARGUMENTS

=over

=item NAME - string - name of the application

=item DATA - hashref - data related to the application.

It may have any of the following properties:

=over

=item token_name - string - OPTIONAL

Name of an API token used by the application.

=item public_key - string - OPTIONAL

Path to a public key used by the application.

=item private_key - string - OPTIONAL

Path to a private key used by the application.

=item jwt - hashref - OPTIONAL

The contents are a JSON Web Token. The contents can vary depending on the application that is linked. This was the token used to initially set up the linkage and may be updated by various processes such as key rotation and token upgrades.

=back

=back

=head3 RETURNS

N/A

=head3 THROWS

=over

=item If the storage directory cannot be created or does not exist.

=item If the storage file cannot be created or accessed.

=item If the updated file cannot be saved.

=back

=cut

sub save ( $self, $name, $data ) {
    $self->_create_directory_if_missing( $self->{path} );
    my $path = $self->{path} . '/' . STORAGE_NAME();

    my $transaction = Cpanel::Transaction::File::JSON->new( path => $path, permissions => $FILE_PERMS );
    $self->_change_data(
        $transaction,
        sub ($applications) {
            $applications->{$name} = $data;
            return 1;
        }
    );
    return;
}

=head2 INSTANCE->remove(NAME)

=head3 ARGUMENTS

=over

=item NAME - string - name of the application

=back

=head3 RETURNS

N/A

=head3 THROWS

=over

=item If the storage directory cannot be created or does not exist.

=item If the storage file cannot be created or accessed.

=item If the updated file cannot be saved.

=back

=cut

sub remove ( $self, $name ) {
    $self->_create_directory_if_missing( $self->{path} );
    my $path        = $self->{path} . '/' . STORAGE_NAME();
    my $transaction = Cpanel::Transaction::File::JSON->new( path => $path, permissions => $FILE_PERMS );
    $self->_change_data(
        $transaction,
        sub ($applications) {
            delete $applications->{$name};
            return 1;
        }
    );
    return;
}

=head2 INSTANCE->load(NAME)

=head3 ARGUMENTS

=over

=item NAME - string - name of the application

=back

=head3 RETURNS

The requested application data, if it exists, or C<undef>, if it does not exist in the data.

The application data will be a hashref with the following fields:

=over

=item name - string

The name of the application that is connected.

=item token_name - string - OPTIONAL

Name of an API token used by the application.

=item public_key - string - OPTIONAL

Path to a public key used by the application.

=item private_key - string - OPTIONAL

Path to a private key used by the application.

=item jwt - hashref - OPTIONAL

The contents are a JSON Web Token. The contents can vary depending on the application that is linked. This was the token used to initially set up the linkage and may be updated by various processes such as key rotation and token upgrades.

=back

=head3 THROWS

=over

=item If the files existence cannot be checked.

=item If the file cannot be opened.

=item If the transaction cannot be set up due to resource constraints or the file already being locked.

=back

=cut

sub load ( $self, $name ) {
    my $apps = $self->_read();
    return ( $apps && $apps->{$name} ) ? { name => $name, %{ $apps->{$name} } } : undef;
}

=head2 INSTANCE->list()

=head3 ARGUMENTS

N/A

=head3 RETURNS

An array with the connected applications configured for this user.

Each element will be a hashref with the following fields:

=over

=item name - string

The name of the application that is connected.

=item token_name - string - OPTIONAL

Name of an API token used by the application.

=item public_key - string - OPTIONAL

Path to a public key used by the application.

=item private_key - string - OPTIONAL

Path to a private key used by the application.

=item jwt - hashref - OPTIONAL

The contents are a JSON Web Token. The contents can vary depending on the application that is linked. This was the token used to initially set up the linkage and may be updated by various processes such as key rotation and token upgrades.

=back

=head3 THROWS

=over

=item If the files existence cannot be checked.

=item If the file cannot be opened.

=item If the transaction cannot be set up due to resource constraints or the file already being locked.

=back

=cut

sub list ($self) {
    Cpanel::Context::must_be_list();

    my $apps = $self->_read();
    return ( ref $apps eq 'HASH' ) ? map { { name => $_, %{ $apps->{$_} } } } keys %$apps : ();
}

=head1 PRIVATE METHODS

=head2 INSTANCE->_read()

Read the storage file for a user.

=head3 RETURNS

The complete parsed storage file, if it exists. If no file yet exists, it will return an empty hashref.

=head3 THROWS

=over

=item If the files existence cannot be checked.

=item If the file cannot be opened.

=item If the transaction cannot be set up due to resource constraints or the file already being locked.

=back

=cut

sub _read ($self) {
    my $path = $self->{path} . '/' . STORAGE_NAME();

    my $apps = {};
    if ( Cpanel::Autodie::exists($path) ) {
        my $reader_transaction = Cpanel::Transaction::File::JSONReader->new( path => $path );
        $apps = $reader_transaction->get_data();
    }

    return $apps;
}

=head2 INSTANCE->_create_directory_if_missing(DIR)

Create the storage directory, if its not present already.

=head3 ARGUMENTS

=over

=item DIR - string

The storage directory for the application data.

=back

=head3 RETURNS

N/A

=head3 THROWS

=over

=item If the directory or one of its parents cannot be created.

=back

=head3 EXAMPLES


=cut

sub _create_directory_if_missing ( $self, $dir ) {

    Cpanel::Mkdir::ensure_directory_existence_and_mode(
        $dir,
        $DIR_PERMS,
    );

    return;
}

=head2 INSTANCE->_change_data(TRANSACTION, CR)

Helper function to make changes to configuration managed by the transaction.

=head3 ARGUMENTS

=over

=item TRANSACTION - Cpanel::Transaction::File::JSON

The transaction processor for the file.

=item CR - coderef

A function to call with the following signature:

  sub dowork(DATA) => 1|0

where DATA is the current configuration or an empty hashref.
The subroutine should return 1 to indicate it changed something
and 0 to indicate there are no changes.

=back

=head3 RETURNS

1 if there were changes, 0 otherwise.

=head3 THROWS

=over

=item When the data cannot be saved to the file.

=item When the supporting resources for the transaction cannot be cleaned up.

=back

=head3 EXAMPLES


=cut

sub _change_data ( $self, $transaction, $cr ) {

    my $data = $transaction->get_data();

    $data = {} if ref $data ne 'HASH';

    my $dirty = $cr->($data);

    if ($dirty) {
        $transaction->set_data($data);
        $transaction->save_and_close_or_die();
    }
    else {
        $transaction->close_or_die();
    }

    $transaction = undef;

    return $dirty;
}

1;
