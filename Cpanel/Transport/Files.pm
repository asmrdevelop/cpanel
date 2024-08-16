
# cpanel - Cpanel/Transport/Files.pm               Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

package Cpanel::Transport::Files;

use strict;
use warnings;
use Cpanel::Locale              ();
use Cpanel::Transport::Response ();

my $locale;
our @valid_transport_types = ( 'FTP', 'SFTP', 'WebDAV', 'Local', 'Custom', 'AmazonS3', 'S3Compatible', 'Rsync', 'GoogleDrive', 'Backblaze' );

sub new {    ## no critic(RequireArgUnpacking) - passing all args for response
    my ( $class, $type, $OPTS, $CFG ) = @_;
    $CFG ||= {};

    # Prevent interface abuse; see SWAT-201
    die "Second argument to $class\->new must be an unblessed HASH reference" unless ref $OPTS eq 'HASH';

    # Prevent a reference loop; see SWAT-165
    # A shallow clone is just fine here
    my $opts_clone = {%$OPTS};

    $locale = _locale();

    if ( !defined $type ) {
        die Cpanel::Transport::Exception::MissingParameter->new(
            \@_, 0,
            $locale->maketext( '“[_1]” is missing the following parameters: [list_and,_2]', ( caller(0) )[3], 'type' )
        );
    }
    if ( !is_transport_type_valid($type) ) {
        die Cpanel::Transport::Response->new(
            \@_, 0,
            $locale->maketext( 'Bad transport type detected. Must be one of: [list_and,_1]', \@valid_transport_types )
        );
    }

    my $ns = "Cpanel::Transport::Files::${type}";
    if ( !exists $INC{"Cpanel/Transport/Files/${type}.pm"} ) {
        eval { require "Cpanel/Transport/Files/${type}.pm"; };    ## no critic(RequireBarewordIncludes) - we are loading a module based on variable
        if ($@) {
            die Cpanel::Transport::Response->new(
                \@_, 0,
                $locale->maketext( 'Could not load “[_1]”: [_2]', $ns, $@ )
            );
        }
    }

    my $ctf_file_obj = $ns->new( $opts_clone, $CFG );
    if ( $ctf_file_obj->isa($ns) ) {

        $ctf_file_obj->{'_rebuild_reqs'} = {
            'class' => $class,
            'type'  => $type,
            'OPTS'  => $OPTS,
            'CFG'   => $CFG,
        };

        $ctf_file_obj->{'ns'} = $ns;
        return $ctf_file_obj;
    }
    else {
        die Cpanel::Transport::Response->new(
            \@_, 0,
            $locale->maketext( 'Could not instantiate “[_1]”.', $ns )
        );
    }
}

# Provide an accessor for subclasses.
sub _locale {
    return $locale ||= Cpanel::Locale->get_handle();
}

sub rebuild {
    my ($self) = @_;

    my $class = $self->{'_rebuild_reqs'}{'class'};
    my $type  = $self->{'_rebuild_reqs'}{'type'};
    my $OPTS  = $self->{'_rebuild_reqs'}{'OPTS'};
    my $CFG   = $self->{'_rebuild_reqs'}{'CFG'};

    return $class->new( $type, $OPTS, $CFG );
}

sub load_module {    ## no critic(RequireArgUnpacking) - passing all args for response
    my ($module) = @_;
    $locale ||= Cpanel::Locale->get_handle();

    eval "require $module;";
    if ($@) {
        die Cpanel::Transport::Response->new(
            \@_, 0,
            $locale->maketext( 'Could not load “[_1]”: [_2]', $module, $@ )
        );
    }
    return;
}

sub is_transport_type_valid {
    my ($type) = @_;
    $type =~ s/\0//g;
    if ( !grep /^$type$/i, @valid_transport_types ) {
        return 0;
    }

    return 1 if exists $INC{"Cpanel/Transport/Files/${type}.pm"};

    return eval "require Cpanel::Transport::Files::$type; 1;";
}

sub value_is_in_range {
    my (%opts) = @_;

    return 0 unless defined $opts{value};
    my $value = $opts{value};

    no warnings 'numeric';
    return 0 if int($value) ne $value;
    return 0 if defined $opts{min} && $value < $opts{min};
    return 0 if defined $opts{max} && $value > $opts{max};
    return 1;
}

# Finds any missing parameters which are required to create a transport object
# And fills in default values for missing parameters which have defaults
# Will return a list of missing parameters for which we cannot assign default values
# The list of missing parameters allows the caller to report them in an error message
sub missing_parameters {
    my ( $type, $param_hashref ) = @_;
    if ( is_transport_type_valid($type) ) {
        my $fn = _get_function( "Cpanel::Transport::Files::${type}", '_missing_parameters' );
        return unless defined $fn;
        return $fn->($param_hashref);
    }
    else {
        return;
    }
}

# Remove any parameters not to be used
# Returns a list of any parameters removed
sub sanitize_parameters {
    my ( $type, $param_hashref, $ignore_ref ) = @_;
    if ( !is_transport_type_valid($type) ) {
        return;
    }

    my $fn = _get_function( "Cpanel::Transport::Files::${type}", '_get_valid_parameters' );
    return unless defined $fn;

    my @valid_params = $fn->();
    push( @valid_params, @$ignore_ref );
    my %valid_params = map { $_ => 1 } @valid_params;

    my $sanitizer = _get_function( "Cpanel::Transport::Files::${type}", '_sanitize_parameter' );

    my @result = ();
    foreach my $key (%$param_hashref) {
        if ( exists $valid_params{$key} ) {
            if ($sanitizer) {
                $param_hashref->{$key} = $sanitizer->( $key, $param_hashref->{$key} );
            }
        }
        else {
            delete $param_hashref->{$key};
            push @result, $key;
        }
    }

    return \@result;
}

# Validate that the parameters have valid values
# Returns a list of params with invalid values
sub validate_parameters {
    my ( $type, $param_hashref ) = @_;
    if ( !is_transport_type_valid($type) ) {
        return;
    }
    my $fn = _get_function( "Cpanel::Transport::Files::${type}", '_validate_parameters' );
    return unless defined $fn;
    return $fn->($param_hashref);
}

sub validate_local_file {
    my ( $self, $file ) = @_;
    if ( !-e $file ) {
        my @caller = caller(1);
        die Cpanel::Transport::Response->new(
            $file, 0,
            $locale->maketext( '“[_1]” attempted to validate a file that does not exist: [_2]', $caller[3], $file )
        );
    }
}

#
# Some types may require additional cleanup after being deleted
#
sub post_deletion_cleanup {
    my ($self) = @_;

    if ( $self->can('_post_deletion_cleanup') ) {
        $self->_post_deletion_cleanup();
    }

    return;
}

sub get_path {
    my ($self) = @_;

    # Default param for storing the path for the destination
    return $self->{'path'};
}

#This assumes that the directory is the first entry in the array response from
# ls(), we may need different logic for determinining this.
sub stat {    ## no critic(RequireArgUnpacking) - passing all args for exception
    my $self = shift;

    die Cpanel::Transport::Exception::NotImplemented->new( \@_ ) if !$self->can('_stat');

    my ($path) = @_;

    if ( !defined $path ) {
        die Cpanel::Transport::Exception::MissingParameter->new(
            \@_, 0,
            $locale->maketext( '“[_1]” is missing the following parameters: [list_and,_2]', ( caller(0) )[3], 'path' )
        );
    }

    my $ls_response = $self->ls($path);
    if ( defined($ls_response) ) {
        $ls_response->{'data'} = $ls_response->{'data'}->[0];
    }
    return $ls_response;
}

# Stub functions to identify undefined methods
sub get {    ## no critic(RequireArgUnpacking) - passing all args for exception
    my $self = shift;

    die Cpanel::Transport::Exception::NotImplemented->new( \@_ ) if !$self->can('_get');

    my ( $remote, $local, ) = @_;
    if ( !defined $local || !defined $remote ) {
        die Cpanel::Transport::Exception::MissingParameter->new(
            \@_, 0,
            $locale->maketext( '“[_1]” is missing the following parameters: [list_and,_2]', ( caller(0) )[3], [qw(remote local)] )
        );
    }
    return $self->_get(@_);
}

sub put {    ## no critic(RequireArgUnpacking) - passing all args for exception
    my $self = shift;
    my ( $local, $remote ) = @_;

    die Cpanel::Transport::Exception::NotImplemented->new( \@_ ) if !$self->can('_put');
    if ( !defined $local || !defined $remote ) {
        die Cpanel::Transport::Exception::MissingParameter->new(
            \@_, 0,
            $locale->maketext( '“[_1]” is missing the following parameters: [list_and,_2]', ( caller(0) )[3], [qw(local remote)] )
        );
    }

    $self->validate_local_file($local);    # This will throw an exception if it broke

    return $self->_put(@_);
}

sub put_inc {    ## no critic(RequireArgUnpacking) - passing all args for exception
    my $self = shift;
    my ( $local, $remote ) = @_;
    die Cpanel::Transport::Exception::NotImplemented->new( \@_ ) if !$self->can('_put_inc');
    if ( !defined $local || !defined $remote ) {
        die Cpanel::Transport::Exception::MissingParameter->new(
            \@_, 0,
            $locale->maketext( '“[_1]” is missing the following parameters: [list_and,_2]', ( caller(0) )[3], [qw(local remote)] )
        );
    }

    $self->validate_local_file($local);    # This will throw an exception if it broke

    return $self->_put_inc(@_);
}

sub ls {
    my $self = shift;
    die Cpanel::Transport::Exception::NotImplemented->new( \@_ ) if !$self->can('_ls');
    return $self->_ls(@_);
}

#
# ls_check - check if the transport has permissions to perform "ls" on
#            a directory.  S3 type transports can have fine-grained permissions
#            such that it may be possible to upload/download files but not
#            list the files in a directory.  With most transports this will
#            not be the case.
#
sub ls_check {
    my $self = shift;

    # Most transports will not implement this as it is not usually needed
    return Cpanel::Transport::Response->new( \@_, 1, 'OK' ) if !$self->can('_ls_check');
    return $self->_ls_check(@_);
}

sub mkdir {    ## no critic(RequireArgUnpacking) - passing all args for exception
    my $self = shift;
    die Cpanel::Transport::Exception::NotImplemented->new( \@_ ) if !$self->can('_mkdir');
    my ($path) = @_;
    if ( !defined $path ) {
        die Cpanel::Transport::Exception::MissingParameter->new(
            \@_, 0,
            $locale->maketext( '“[_1]” is missing the following parameters: [list_and,_2]', ( caller(0) )[3], 'path' )
        );
    }
    return $self->_mkdir(@_);
}

sub chdir {    ## no critic(RequireArgUnpacking) - passing all args for exception
    my $self = shift;
    die Cpanel::Transport::Exception::NotImplemented->new( \@_ ) if !$self->can('_chdir');
    my ($path) = @_;

    if ( !defined $path ) {
        die Cpanel::Transport::Exception::MissingParameter->new(
            \@_, 0,
            $locale->maketext( '“[_1]” is missing the following parameters: [list_and,_2]', ( caller(0) )[3], 'path' )
        );
    }

    return $self->_chdir(@_);
}

sub rmdir {    ## no critic(RequireArgUnpacking) - passing all args for exception
    my $self = shift;

    die Cpanel::Transport::Exception::NotImplemented->new( \@_ ) if !$self->can('_rmdir');

    my ($path) = @_;
    if ( !defined $path ) {
        die Cpanel::Transport::Exception::MissingParameter->new(
            \@_, 0,
            $locale->maketext( '“[_1]” is missing the following parameters: [list_and,_2]', ( caller(0) )[3], 'path' )
        );
    }

    return $self->_rmdir(@_);
}

sub delete {    ## no critic(RequireArgUnpacking) - passing all args for exception
    my $self = shift;

    die Cpanel::Transport::Exception::NotImplemented->new( \@_ ) if !$self->can('_delete');

    my ($path) = @_;
    if ( !defined $path ) {
        die Cpanel::Transport::Exception::MissingParameter->new(
            \@_, 0,
            $locale->maketext( '“[_1]” is missing the following parameters: [list_and,_2]', ( caller(0) )[3], 'path' )
        );
    }

    return $self->_delete(@_);
}

sub pwd {
    my $self = shift;
    die Cpanel::Transport::Exception::NotImplemented->new( \@_ ) if !$self->can('_pwd');
    return $self->_pwd(@_);
}

sub _parse_ls_response {
    my ( $self, $line ) = @_;
    my ( $perms, undef, $user, $group, $size, $month, $day, $time, $filename ) = split( ' ', $line, 9 );
    my $type;
    return if $line =~ /^total\s+\d+/;

    # Some FTP servers return very weird responses.
    if ( $line =~ /^(\d{2})-(\d{2})-\d{2}\s+(\d{2}):(\d{2})([AP])M\s+<(DIR|FILE)>\s+(.*)/ ) {
        ( $month, $day, $type, $filename ) = ( $1, $2, $6, $7 );
        my ( $hour, $minute ) = ( $3, $4 );
        $hour = 0 if $hour == 12;
        $hour += 12 if $5 eq "P";
        $time  = sprintf "%02d:%02d", $hour, $minute;
        $perms = $user = $group = $size = -1;
        $type  = $type eq "DIR" ? "d" : ( $filename =~ / -> / ? "l" : "f" );
    }

    my %response = (
        'size'     => $size,
        'filename' => $filename,
        'user'     => $user,
        'group'    => $group,

    );

    # Determine node type
    $type ||= substr( $perms, 0, 1 );

    if ( $type eq 'd' ) {
        $response{'type'} = 'directory';
    }
    elsif ( $type eq 'l' ) {
        $response{'type'} = 'symlink';
        my $destination;
        ( $filename, $destination ) = split( ' -> ', $filename );
        $response{'symlink_destination'} = $destination;
        $response{'filename'}            = $filename;
    }
    else {
        $response{'type'} = 'file';
    }

    require Cpanel::FileUtils::Permissions::String;
    $response{'perms'} = $perms eq "-1" ? $perms : Cpanel::FileUtils::Permissions::String::str2oct($perms);
    return \%response;
}

sub _get_function {
    my ( $namespace, $function ) = @_;
    if ( !exists $INC{"$namespace.pm"} ) {
        eval { require $namespace; 1; };
    }
    return eval { $namespace->can($function) };
}

1;
