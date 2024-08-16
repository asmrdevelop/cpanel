package Cpanel::SpamAssassin::Config;

# cpanel - Cpanel/SpamAssassin/Config.pm           Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use strict;
use warnings;

use Cpanel::Exception           ();
use Cpanel                      ();
use Cpanel::FileUtils::LinkTest ();

use constant {
    _ENOENT => 2,

    #referenced from tests
    SPAM_ASSASSIN_FOLDER_PERMS => 0700,
};

our $_GLOBAL_ENABLE_FILE   = '/etc/global_spamassassin_enable';
our $_SPAM_ASSASSIN_FOLDER = '.spamassassin';
our $_USER_PREFS_FILE      = "$_SPAM_ASSASSIN_FOLDER/user_prefs";

=encoding utf-8

=head1 NAME

Cpanel::SpamAssassin::Config - Configuration management for SpamAssassin

=head1 SYNOPSIS

    use Cpanel::SpamAssassin::Config;

    Cpanel::SpamAssassin::Config::who_enabled();
    Cpanel::SpamAssassin::Config::get_config_option('required_score');
    Cpanel::SpamAssassin::Config::get_user_preferences();
    Cpanel::SpamAssassin::Config::update_user_preference('required_score',8);

=head1 DESCRIPTION

Configuration management for SpamAssassin

=cut

=head2 globally_enabled

Determines if SpamAssassin is globally enabled

=over 2

=item Output

=over 3

=item C<Boolean>

    Returns truthy if SpamAssassin is globally enabled, falsey if not

=back

=back

=cut

sub globally_enabled {
    return Cpanel::FileUtils::LinkTest::get_type($_GLOBAL_ENABLE_FILE);
}

=head2 who_enabled

Determine who enabled SpamAssassin

=over 2

=item Output

=over 3

=item C<SCALAR>

    returns 'global' or 'user' according to who enabled SpamAssassin

=back

=back

=cut

sub who_enabled {
    _assert_homedir();

    require Cpanel::Server::Type::Role::SpamFilter;
    return undef if !Cpanel::Server::Type::Role::SpamFilter->is_enabled();

    return 'global' if globally_enabled();

    return 'user' if Cpanel::FileUtils::LinkTest::get_type("$Cpanel::homedir/.spamassassinenable");

    return undef;
}

=head2 get_config_option

get the value of a specified key in the SpamAssassin configurations

=over 2

=item Input

=over 3

=item C<SCALAR>

    $want_option - key of the configuration to return

=back

=item Output

=over 3

=item C<SCALAR|ARRAY>

    returns an array or a scalar depending on the context in which this is called
    in the case that it is not in array context, it returns the first value it
    finds that matches the existing key

=back

=back

=cut

sub get_config_option {
    my $want_option = shift;

    _assert_homedir();

    return if !$want_option;

    my $configs = get_user_preferences();
    return if !$configs;

    return if !exists $configs->{$want_option};

    my @values = @{ $configs->{$want_option} };

    return wantarray ? @values : shift @values;
}

=head2 get_user_preferences

Return parsed hash of SpamAssassin config options OR undef
if the there is no configuration.

=over 2

=item Output

Returns undef if there is no configuration information; otherwise:

=over 3

=item C<HASHREF>

    hash ref containing keys representing existing SpamAssassin config keys and
    an array of their cooresponding values

    {
        required_score => ['8'],
        whitelist_from => ['argh1','argh2'],
        blacklist_from => ['blarb1'],
        * => [*]
    }

=back

=back

=cut

sub get_user_preferences {

    _assert_homedir();
    _ensure_spamassassin_folder();

    my $prefs_file = "$Cpanel::homedir/" . $_USER_PREFS_FILE;

    if ( !-e $prefs_file ) {
        if ( $! != _ENOENT() ) {
            warn "stat($prefs_file): $!";
        }

        return undef;
    }

    require Cpanel::Transaction::File::LoadConfigReader;

    my $prefs_trans = Cpanel::Transaction::File::LoadConfigReader->new( path => $prefs_file, delimiter => ' ', use_hash_of_arr_refs => 1 );

    return $prefs_trans->get_data();

}

=head2 update_user_preference

Update the value or values of a key in the SpamAssassin user preferences user preference

=over 2

=item Input

=over 3

=item C<SCALAR>

    key to update in the user_pref file

=item C<ARRAYREF>

    values to update in the user_pref file that coorelate to the key

=back

=item Output

=over 3

=item C<HASHREF>

    returns the parsed updated user_pref file with the new values

=back

=back

=cut

sub update_user_preference {
    my ( $updated_key, $updated_values ) = @_;

    _assert_homedir();
    _ensure_spamassassin_folder();

    my $prefs_file = "$Cpanel::homedir/" . $_USER_PREFS_FILE;

    require Cpanel::Transaction::File::LoadConfig;

    my $prefs_trans = eval { Cpanel::Transaction::File::LoadConfig->new( path => $prefs_file, delimiter => ' ', use_hash_of_arr_refs => 1 ) };
    die Cpanel::Exception::create( 'IO::FileOpenError', [ path => $prefs_file, error => $@ ] ) if !$prefs_trans;

    my $user_pref = $prefs_trans->get_data();
    $user_pref->{$updated_key} = $updated_values;

    $prefs_trans->set_data($user_pref);
    $prefs_trans->save_or_die( allow_array_values => 1 );

    return $prefs_trans->get_data();
}

sub _ensure_spamassassin_folder {
    my $folder_path = "$Cpanel::homedir/$_SPAM_ASSASSIN_FOLDER";

    if ( -e $folder_path ) {
        if ( ( stat _ )[2] & 0777 != SPAM_ASSASSIN_FOLDER_PERMS() ) {
            chmod SPAM_ASSASSIN_FOLDER_PERMS, $folder_path or do {
                warn "chmod($folder_path): $!";
            };
        }
    }
    else {
        require Cpanel::Mkdir;
        return Cpanel::Mkdir::ensure_directory_existence_and_mode( $folder_path, SPAM_ASSASSIN_FOLDER_PERMS() );
    }

    return;
}

sub _assert_homedir {
    die 'No $Cpanel::homedir!' if !$Cpanel::homedir;
    return;
}

1;
