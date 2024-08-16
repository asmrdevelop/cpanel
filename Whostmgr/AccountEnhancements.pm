package Whostmgr::AccountEnhancements;

# cpanel - Whostmgr/AccountEnhancements.pm           Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use cPstrict;
use Cpanel::Imports;
use Cpanel::Context                                   ();
use Cpanel::Hooks                                     ();
use Cpanel::ConfigFiles                               ();
use Cpanel::StringFunc::Trim                          ();
use Cpanel::Transaction::File::JSON                   ();
use Cpanel::Fcntl::Constants                          ();
use Cpanel::Validate::FilesystemPath                  ();
use Cpanel::Autodie                                   ();
use Cpanel::Exception                                 ();
use Whostmgr::AccountEnhancements::Validate           ();
use Whostmgr::AccountEnhancements::AccountEnhancement ();

=encoding utf-8

=head1 NAME

Whostmgr::AccountEnhancements.pm

=head1 DESCRIPTION

WHM functions for managing the cPanel user account enhancement data structure.

=head1 FUNCTIONS

=head2 add( $name, $id )

=head3 ARGUMENTS

=over

=item name - string

Required. The name for the account enhancement you want to add.

=item id - string

Required. The identifier for the account enhancement you want to add.

=back

=head3 THROWS

=over

=item When the user does not have root privileges.

=item validate_name

Throws an "InvalidParameter" exception if 'name' parameter is invalid.

=item validate_id

Throws an "InvalidParameter" exception if 'id' parameter is invalid.

=item name_exists

Throws an "InvalidParameter" exception if AccountEnhancement with 'name' parameter already exists.

=back

=head3 RETURNS

Returns the result of _persist(), which is the AccountEnhancements object.

=cut

sub add ( $name, $id ) {

    Whostmgr::AccountEnhancements::Validate::validate_admin_only();
    Cpanel::Autodie::mkdir_if_not_exists( $Cpanel::ConfigFiles::ACCOUNT_ENHANCEMENTS_DIR, 0700 );
    Whostmgr::AccountEnhancements::Validate::validate_name($name);
    Whostmgr::AccountEnhancements::Validate::validate_id($id);
    Whostmgr::AccountEnhancements::Validate::name_exists($name);

    $name = Cpanel::StringFunc::Trim::ws_trim($name);
    my $enhancement = Whostmgr::AccountEnhancements::AccountEnhancement->new( name => $name, id => $id );

    _run_hook( 'AccountEnhancements::Add', 'pre', $enhancement->TO_JSON );

    $enhancement = _persist($enhancement);

    _run_hook( 'AccountEnhancements::Add', 'post', $enhancement->TO_JSON );

    return $enhancement;
}

=head2 list( )

This function lists current account enhancements.

=head3 RETURNS

This function returns a reference to an array that lists the account enhancements.

=head3 THROWS

=over 1

=item When the user does not access via ACL

=item When not called in list context

=item When the system fails to load enhancements

=back

=cut

sub list() {

    Cpanel::Context::must_be_list();

    my @enhancements;
    my @warnings;

    # currently errors/warnings show in the create/modify UI's, this allow list to return empty and prevent it.
    my $access = eval { Whostmgr::AccountEnhancements::Validate::validate_access() };

    if ($access) {
        my $files = _list_enhancement_files();
        foreach my $filename (@$files) {
            my $enhancement = _load_enhancement_data($filename);
            next unless ref $enhancement eq 'HASH';
            foreach my $data_type (qw(name id)) {
                if ( !$enhancement->{$data_type} ) {
                    push @warnings, Cpanel::Exception->create_raw( locale()->maketext( "The “[_1]” enhancement file contains incomplete or corrupt data.", $filename ) );
                    next;
                }

                _validate_data_type( $data_type, $enhancement->{$data_type} )
                  or push @warnings, Cpanel::Exception->create_raw( locale()->maketext( "The “[_1]” enhancement contains the invalid “[_2]” value: [_3]", $enhancement->{'name'}, $data_type, $enhancement->{$data_type} ) );
            }
            push( @enhancements, Whostmgr::AccountEnhancements::AccountEnhancement->new( thaw => $enhancement ) );
        }

    }
    @enhancements = sort { lc( $a->{name} ) cmp lc( $b->{name} ) } @enhancements;

    return ( \@enhancements, \@warnings );
}

=head2 list_unique_ids( )

This function lists current account enhancements.

=head3 RETURNS

This function returns a reference to a hash that lists Account Enhancements with a unique ID.

=head3 THROWS

=over 1

=item When the user does not access via ACL

=item When not called in list context

=item When the system fails to load enhancements

=back

=cut

sub list_unique_ids() {
    my ( $list, $warnings ) = list();

    require Whostmgr::AccountEnhancements::Install;
    my @installed_ids = map { $_->{id} } values %{ Whostmgr::AccountEnhancements::Install::get_installed_plugins() };
    my %seen;
    my @unique = grep {
        my $ae = $_;
        defined $ae->{id}
          && !$seen{ $ae->{id} }++
          && grep $ae->{id} eq $_, @installed_ids
    } @{$list};

    return ( \@unique, $warnings );
}

=head2 update($name, %updates)

This function updates an account enhancement.

=head3 ARGUMENTS

=over

=item name - string

The name of the account enhancement.

=item %updates - hash

A hash containing the key => value pairs to update.

=back

=head3 RETURNS

This function returns the updated AccountEnhancement object upon success.

=head3 THROWS

=over 1

=item When the user does not have root privileges

=item When no values are supplied to update.

=item When find fails.

=item When an invalid name is passed.

=item When the id is invalid, if supplied.

=back

=cut

sub update ( $name, %updates ) {

    Whostmgr::AccountEnhancements::Validate::validate_admin_only();
    die Cpanel::Exception::create( "InvalidParameter", "You must provide updated values to update an enhancement." )
      if !$updates{name} && !$updates{id};

    my $enhancement = Whostmgr::AccountEnhancements::find($name);

    if ( $updates{'id'} ) {
        Whostmgr::AccountEnhancements::Validate::validate_id( $updates{'id'} );
        $enhancement->set_id( $updates{'id'} );
    }

    return _persist($enhancement);
}

=head2 delete($name)

This function removes an account enhancement by name.

=head3 ARGUMENTS

=over

=item name - string

The name of the account enhancement.

=back

=head3 RETURNS

This function returns 1 if the enhancement file was deleted

=head3 THROWS

=over 1

=item When the name is not valid via l<AccountEnhancements::Validate::validate_name>

=item When L<Cpanel::Autodie::CORE::unlink> fails

=back

=head3 THROWS

=over 1

=item When the user does not have root privileges

=item When the enhancement name is invalid

=back

=cut

sub delete ($name) {

    Whostmgr::AccountEnhancements::Validate::validate_admin_only();
    Whostmgr::AccountEnhancements::Validate::validate_name($name);
    my $path = $Cpanel::ConfigFiles::ACCOUNT_ENHANCEMENTS_DIR . '/' . $name . '.json';

    Cpanel::Autodie::unlink($path);

    return 1;
}

=head2 find($name)

This function retrieves an account enhancement by name.

=head3 ARGUMENTS

=over

=item name - string

The name of the account enhancement.

=back

=head3 RETURNS

This function returns the AccountEnhancement object upon success.

=head3 THROWS

=over 1

=item When the user does not have access via ACL

=item When the name is invalid

=item Throws when no enhancement could be found.

=back

=cut

sub find ($name) {

    Whostmgr::AccountEnhancements::Validate::validate_access();
    Whostmgr::AccountEnhancements::Validate::validate_name($name);
    my $enhancement_path = $Cpanel::ConfigFiles::ACCOUNT_ENHANCEMENTS_DIR . '/' . $name . '.json';
    my $enhancement_data = _load_enhancement_data($enhancement_path);
    die Cpanel::Exception::create( "InvalidParameter", "The system was unable to find the “[_1]” enhancement.", [$name] ) if !$enhancement_data;
    return Whostmgr::AccountEnhancements::AccountEnhancement->new( thaw => $enhancement_data );

}

=head2 findByAccount($account)

This function returns an arrayref of valid account enhancements assigned to the specified $account username.

=head3 ARGUMENTS

=over

=item $account - string

The account username.

=back

=head3 RETURNS

This function returns an list containing any warnings and AccountEnhancement objects upon success.

=over 1

=item enhancements - an ARRAYREF of enhancement objects

=item warnings - an ARRAYREF of strings

=back

=head3 THROWS

=over 1

=item When the user does not have access via ACL.

=item When the account could not could be found.

=item When the account cannot be accessed by the current user.

=item When the system fails to load the accounts configuration.

=back

=cut

sub findByAccount ($account) {

    Cpanel::Context::must_be_list();
    Whostmgr::AccountEnhancements::Validate::validate_access();

    require Cpanel::Config::CpUserGuard;
    require Whostmgr::Authz;
    require Cpanel::AcctUtils::Account;

    Cpanel::AcctUtils::Account::accountexists_or_die($account);
    Whostmgr::Authz::verify_account_access($account);

    my $userdata = Cpanel::Config::CpUserGuard->new($account);
    die locale()->maketext( "The system could not load the [asis,cpuser] file for the “[_1]” account.", $account ) if !$userdata;

    my ( @enhancements, @warnings );
    foreach my $assignments ( grep { /^ACCOUNT-ENHANCEMENT-/ } keys %{ $userdata->{'data'} } ) {
        my $id = $assignments =~ s/ACCOUNT-ENHANCEMENT-//r;

        # AC from DUCK-5111, Account Enhancement assignments remain on the account level when the Account Enhancement is removed (deleted)
        # so it is expected some could be there, but not found using find()
        my $enhancement = eval { Whostmgr::AccountEnhancements::find($id) };
        push( @warnings,     $@ )           if $@;
        push( @enhancements, $enhancement ) if $enhancement;
    }
    return ( \@enhancements, \@warnings );

}

=head2 assign($name, $account)

This function assigns an account enhancement to an account.

=head3 ARGUMENTS

=over

=item name - string

The name of the account enhancement.

=item account - string

The username of the account.

=back

=head3 RETURNS

This function returns 1 upon success.

=head3 THROWS

=over 1

=item When the user does not have access via ACL.

=item When no enhancement could be found.

=item When AccountEnhancement::add_account fails

=back

=cut

sub assign ( $name, $account ) {

    Whostmgr::AccountEnhancements::Validate::validate_access();
    my $enhancement = Whostmgr::AccountEnhancements::find($name);
    Whostmgr::AccountEnhancements::Validate::validate_id( $enhancement->get_id() );
    _run_hook( 'AccountEnhancements::Assign', 'pre', $enhancement->TO_JSON );
    $enhancement->add_account($account);

    _run_hook( 'AccountEnhancements::Assign', 'post', $enhancement->TO_JSON );

    return 1;

}

=head2 unassign($name, $account)

This function removes an account enhancement from an account.

=head3 ARGUMENTS

=over

=item name - string

The name of the account enhancement.

=item account - string

The username of the account.

=back

=head3 RETURNS

This function returns 1 upon success.

=head3 THROWS

=over 1

=item When the user does not have access via ACL.

=item When no enhancement could be found.

=item When AccountEnhancement::remove_account fails

=back

=cut

sub unassign ( $name, $account ) {

    Whostmgr::AccountEnhancements::Validate::validate_access();
    my $enhancement = eval { Whostmgr::AccountEnhancements::find($name) };
    my $exception   = $@;

    # Attempt the unassign even if the enhancement is removed
    # by loading from userdata
    if ($exception) {

        require Cpanel::Config::CpUserGuard;
        my $userdata = Cpanel::Config::CpUserGuard->new($account);
        my $key      = "ACCOUNT-ENHANCEMENT-${name}";

        if ( !$userdata || !exists $userdata->{'data'}{$key} ) {
            die $exception;
        }

        $enhancement = Whostmgr::AccountEnhancements::AccountEnhancement->new( name => $name, 'id' => $userdata->{'data'}{$key} );

    }

    _run_hook( 'AccountEnhancements::Unassign', 'pre', $enhancement->TO_JSON );
    $enhancement->remove_account($account);
    _run_hook( 'AccountEnhancements::Unassign', 'post', $enhancement->TO_JSON );

    return 1;

}

=head2 _persist( $enhancement )

This function creates the user's account enhancement data file.

=head3 ARGUMENTS

=over

=item enhancement - AccountEnhancement object

Required. This is the AccountEnhancement object.

=back

=head3 RETURNS

This function returns the AccountEnhancement object you passed in.

=head3 THROWS

=over 1

=item When the user does not have root privileges.

=item When the path is invalid

=item When other filesystem operations fail

=back

=cut

sub _persist ($enhancement) {

    Whostmgr::AccountEnhancements::Validate::validate_admin_only();
    my $path = $Cpanel::ConfigFiles::ACCOUNT_ENHANCEMENTS_DIR . '/' . $enhancement->get_name() . '.json';
    Cpanel::Validate::FilesystemPath::die_if_any_relative_nodes($path);
    my $enhancement_file_transaction = Cpanel::Transaction::File::JSON->new(
        path        => $path,
        permissions => 0644,
    );
    $enhancement_file_transaction->set_data($enhancement);
    $enhancement_file_transaction->save_or_die();
    $enhancement_file_transaction->close_or_die();

    return $enhancement;
}

=head2 _list_enhancement_files()

This function lists the files in ACCOUNT_ENHANCEMENTS_DIR.

=head3 THROWS

=over

=item When the user does not have access via ACL.

=item When the name parameter is invalid.

=item When other file system operations fail

=back

=head3 RETURNS

Returns an array reference for the list of files in ACCOUNT_ENHANCEMENTS_DIR.

=cut

sub _list_enhancement_files() {

    Whostmgr::AccountEnhancements::Validate::validate_access();
    my @files;
    if ( Cpanel::Autodie::opendir_if_exists( my $handle, $Cpanel::ConfigFiles::ACCOUNT_ENHANCEMENTS_DIR ) ) {
        foreach my $item ( readdir($handle) ) {
            my $absolute_path = $Cpanel::ConfigFiles::ACCOUNT_ENHANCEMENTS_DIR . "/${item}";
            if ( $item =~ /(.+)\.json\z/ && -f $absolute_path ) {
                my $name = $1;
                push( @files, $absolute_path ) if ( eval { Whostmgr::AccountEnhancements::Validate::validate_name($name) } );
            }
        }
        Cpanel::Autodie::closedir($handle);
    }

    return \@files;
}

=head2 _run_hook($event, $stage, $args)

This function runs a hook for the event at a given stage.

=head3 ARGUMENTS

=over 1

=item $event - string

The hook event.

=item $stage - string

The hook stage.

=item $args

The hook event arguments passed to the hook.

=back

=head3 THROWS

Throws when the hook result is non-zero from C<Cpanel::Hooks::hook>.

=cut

sub _run_hook ( $event, $stage, $args ) {

    my ( $hook_result, $hook_messages ) = Cpanel::Hooks::hook(
        {
            'category' => 'Whostmgr',
            'event'    => $event,
            'stage'    => $stage,
            'blocking' => 1,
        },
        $args,
    );

    if ( !$hook_result ) {
        my $hook_message = int @{$hook_messages} ? join "\n", @{$hook_messages} : '';
        die Cpanel::Exception->create_raw( locale()->maketext( 'The “[_1]” hook denied this operation with the following error: [_2]', $event, $hook_message ) );
    }

    return 1;

}

=head2 _load_enhancement_data($enhancement_file)

This function loads data from a JSON account enhancement file.

=head3 ARGUMENTS

=over 1

=item $enhancement_file - string

The absolute path to the account enhancement file.

=back

=head3 THROWS

=over

=item When the user does not have access via ACL.

=item If the provided enhancement file can't be opened or doesn't exist.

=back

=head3 RETURNS

Returns an array reference for the list of files in ACCOUNT_ENHANCEMENTS_DIR.

=cut

sub _load_enhancement_data ($enhancement_file) {
    Whostmgr::AccountEnhancements::Validate::validate_access();
    my $enhancement_file_transaction = Cpanel::Transaction::File::JSON->new(
        path          => $enhancement_file,
        sysopen_flags => $Cpanel::Fcntl::Constants::O_RDONLY
    ) or die Cpanel::Exception::create( "InvalidParameter", "The system could not find or open the following enhancement path: [_1]", [$enhancement_file] );
    my $enhancement_data = $enhancement_file_transaction->get_data();
    $enhancement_file_transaction->close_or_die();

    return $enhancement_data;
}

=head2 _validate_data_type($data_type, $data_to_validate)

This function loads data from a JSON account enhancement file.

=head3 ARGUMENTS

=over 1

=item $data_type - string

The data type to validate as. The options include 'id' or 'name'.

=item $data_to_validate - string

The data string to validate.

=back

=head3 RETURNS

Returns 1 if a valid data type is provided and the data string passes validation. Returns 0 otherwise.

=cut

sub _validate_data_type ( $data_type, $data_to_validate ) {
    local $@;

    if ( $data_type eq 'id' ) {
        eval { Whostmgr::AccountEnhancements::Validate::validate_id($data_to_validate) };
    }
    elsif ( $data_type eq 'name' ) {
        eval { Whostmgr::AccountEnhancements::Validate::validate_name($data_to_validate) };
    }
    else {
        return 0;
    }

    return $@ ? 0 : 1;
}

1;
