package Whostmgr::Services::SSH::Config;

# cpanel - Whostmgr/Services/SSH/Config.pm         Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use strict;
use warnings;

use Try::Tiny;

use Cpanel::Debug      ();
use Cpanel::Exception  ();
use Cpanel::LoadModule ();

our $VERSION   = 0.2;
our @locations = ( '/usr/local/etc/ssh', '/etc/ssh' );

# Used for special values that can have multiple statements
my %multi_keys = (
    'acceptenv'     => 1,
    'allowgroups'   => 1,
    'allowusers'    => 1,
    'denygroups'    => 1,
    'denyusers'     => 1,
    'hostkey'       => 1,
    'listenaddress' => 1,
    'port'          => 1,
);

=head1 NAME

Whostmgr::Services::SSH::Config - Read and update sshd_config files.

=head1 DESCRIPTION

This class allows for simple inspection of the servers's sshd_config file, and
for safe updates to the SSHD configuration. All changes are tested before they
are applied and rolled back if they do not pass a syntax test.

=head1 SYNOPSIS

  use Whostmgr::Services::SSH::Config ();
  use Try::Tiny;

  my $conf_obj = Whostmgr::Services::SSH::Config->new();
  my $usedns_setting = $conf_obj->get_config("UseDNS");
  my $full_config = $conf_obj->get_config();

  try {
      $conf_obj->set_config({"UseDNS" => "on"});
  }
  catch {
      print "Failed to update sshd_config: $_\n";
  }

=head1 METHODS

=over

=item new(%options)

Class method to create new Whostmgr::Services::SSH::Config objects.

This constructor takes the following options:

=over

=item filename

Sets the filename to use for the sshd_config file. If not provided, this
setting will  be determined by calling the C<filename> method.

=item permissions

Sets the permissions setting to use with the internal transaction object that
handles the actual file reading and writing. Defaults to 0600.

=back

=cut

sub new {
    my ( $class, %options ) = @_;
    my $self = bless {
        _current_diff     => '',
        _sshd_test_output => ''
    }, $class;

    $self->filename( $options{filename} );
    $self->permissions( $options{permissions} // 0600 );

    return $self;
}

=item filename($filename)

Method to get and set the location of the sshd_config file. Sets the sshd_config
file to use when called with a filename argument. If no filename argument is
supplied, this method will return the previously set filename of search for the
sshd_config file on disk.

Throws IO::FileNotFound if the provided filename cannot be located on disk.
Throws Services::NotConfigured if no sshd_config can be located.

=cut

sub filename {
    my ( $self, $filename ) = @_;

    if ( defined $filename ) {
        die Cpanel::Exception::create( 'IO::FileNotFound', [ path => $filename ] ) unless -e $filename;
        $self->{_filename} = $filename;
    }

    return $self->{_filename} if defined $self->{_filename};

    unless ( defined $self->{_filename} ) {
        foreach my $dir (@locations) {
            my $test_file = "$dir/sshd_config";
            if ( -e $test_file ) {
                $self->{_filename} = $test_file;
                last;
            }
        }
    }

    die Cpanel::Exception::create( 'Services::NotConfigured', [ service => 'sshd', reason => "sshd_config missing" ] ) unless defined $self->{_filename};

    return $self->{_filename};
}

=item permisions($permissions)

Method to get or set the default permisions to use with the sshd_config file.

=cut

sub permissions {
    my ( $self, $permissions ) = @_;
    if ( defined $permissions ) {
        $self->{_permissions} = $permissions;
    }
    return $self->{_permissions};
}

=item get_config($directive)

Method to get the configuration settings for sshd_config. When called with
a directive as an argument, returns the setting for that one directive. When
called without arguments, returns a hashref will the entire sshd_config state.

=cut

sub get_config {
    my ( $self, $directive ) = @_;

    my $sshd_config;

    if ( defined $self->{'_cache'} ) {
        $sshd_config = $self->{'_cache'};
    }
    else {
        $sshd_config = {};

        foreach my $line ( split( /\n/, $self->get_raw_conf() ) ) {
            next if $line =~ m/^\s*#/;
            last if $line =~ m/^\s*Match/i;

            # support both formats for key and value pairs
            # key value      (whitespace)
            # key = value    (= sign)
            $line =~ s/^\s*//;    # strip leading spaces
            my ( $name, $value ) = split /(?:\s*=\s*|\s+)/, $line, 2;
            next if !$value || !$name;
            my @values = split /\s+/, $value;
            $name = lc($name);

            if ( exists $multi_keys{$name} ) {
                push @{ $sshd_config->{$name} }, @values;
            }
            elsif ( scalar @values > 1 ) {
                $sshd_config->{$name} = \@values;
            }
            else {
                $sshd_config->{$name} = shift @values;
            }
        }

        $self->{'_cache'} = $sshd_config;
    }

    if ( defined $directive ) {
        $directive = lc($directive);
        return $sshd_config->{$directive};
    }

    return $sshd_config;
}

=item get_raw_conf()

Method to get the unparsed contents of the sshd configuration file. The data
is returned as a single scalar value.

=cut

sub get_raw_conf {
    my $self = shift;
    return ${ $self->_transaction()->get_data() };
}

=item set_config($config_settings)

Method to set one or more sshd_config settings to specific values. The settings
should be specified as a hashref. Settings which take multiple values may be
provided as a pre-joined scalar value or as a hashref.

The C<set_config> method internally calls C<save>, so there is no need to save
the changes manually.

Configuration settings may be specified with any capitalization. The SSH daemon
does not differentiate based on case. If the directive is already present in the
sshd_config file, the capitalization used in the file will be preserved. If the
directive is not already present in the file, the capitaliztion specified in
the config_settings will be used.

If a directive is specified twice in the config_settings with different
capitalization, an exception will be thrown.

=cut

sub set_config {
    my ( $self, $sshd_config ) = @_;

    my %sshd_config_hash = %{$sshd_config};
    my %conf_case_map    = map { lc($_) => $_ } keys %sshd_config_hash;
    if ( scalar keys %sshd_config_hash != scalar keys %conf_case_map ) {
        die Cpanel::Exception::create( 'NameConflict', 'Identical settings with different capitalization were supplied.' );
    }

    # Update existing config
    my $key_regex = join( '|', map { quotemeta( lc($_) ) } sort keys %sshd_config_hash );

    $self->{_last_conf_contents} = $self->get_raw_conf();
    my @old_content = split( /^/, $self->{_last_conf_contents} );
    my @new_content;
    my $current_index;
    for ( $current_index = 0; $current_index <= $#old_content; $current_index++ ) {
        my $line = $old_content[$current_index];
        last if ( $line =~ /^\s*match/i );

        # support both formats for key and value pairs
        # key value      (whitespace)
        # key = value    (= sign)
        if ( $line =~ m/^\s*($key_regex)(?:\s*=\s*|\s+)/i ) {
            my $key    = $1;
            my $lc_key = lc($key);
            next if !defined $sshd_config_hash{ $conf_case_map{$lc_key} };    # Skip previously seen entries
            if ( exists $multi_keys{$lc_key} && ref $sshd_config_hash{ $conf_case_map{$lc_key} } eq 'ARRAY' ) {
                foreach my $value ( @{ $sshd_config_hash{ $conf_case_map{$lc_key} } } ) {
                    push @new_content, "$key $value\n";
                }
            }
            else {
                push @new_content, "$key " . ( ref $sshd_config_hash{ $conf_case_map{$lc_key} } eq 'ARRAY' ? join "\t", @{ $sshd_config_hash{ $conf_case_map{$lc_key} } } : $sshd_config_hash{ $conf_case_map{$lc_key} } ) . "\n";
            }
            $sshd_config_hash{ $conf_case_map{$lc_key} } = undef;             # Mark entry as updated
        }
        else {
            push @new_content, $line;
        }
    }

    $new_content[-1] .= "\n" if scalar @new_content && $new_content[-1] !~ /\n/;

    # Add in new configuration items that didn't exist in file
    foreach my $key ( sort keys %sshd_config_hash ) {
        next if !defined $sshd_config_hash{$key};
        my $lc_key = lc($key);
        if ( exists $multi_keys{$lc_key} && ref $sshd_config_hash{$key} eq 'ARRAY' ) {
            foreach my $value ( @{ $sshd_config_hash{$key} } ) {
                push @new_content, "$key $value\n";
            }
        }
        else {
            push @new_content, "$key " . ( ref $sshd_config_hash{$key} eq 'ARRAY' ? join "\t", @{ $sshd_config_hash{$key} } : $sshd_config_hash{$key} ) . "\n";
        }
    }

    # Bring back in the Match blocks we did not want to parse.
    push( @new_content, @old_content[ $current_index .. $#old_content ] ) if $current_index <= $#old_content;

    # Save
    $self->set_raw_conf( join( '', @new_content ) );
    $self->save();
    return 1;
}

=item set_raw_conf($cont_string)

Method to update the sshd_conf file with new content. This
method does not automatically call the C<save> method.

=cut

sub set_raw_conf {
    my ( $self, $new_contents ) = @_;
    return $self->_transaction->set_data( \$new_contents );
}

=item save()

Method to save the sshd_config. Saving will only take place if the new conf
file passes a syntax text.

=cut

sub save {
    my $self         = shift;
    my $test_closure = sub {
        $self->_test_sshd_conf(@_);
    };
    return $self->_transaction->save_or_die( validate_cr => $test_closure );
}

=item current_diff($diff_text)

Method to retrieve the last applied diff from C<set_config>. Returns an
empty string when no changes have been applied.

=cut

sub current_diff {
    my ($self) = @_;
    if ( $self->{_last_conf_contents} ) {
        Cpanel::LoadModule::load_perl_module("Text::Diff");
        return scalar Text::Diff::diff( \$self->{_last_conf_contents}, $self->_transaction->get_data(), { STYLE => 'Unified' } );
    }
    return "";
}

=item sshd_test_output($output_text)

Method to set and retrieve the last output from sshd -t when attempting to save
the sshd_conf file. In the case of a syntax error during C<save>, this should
contain the error message.

=cut

sub sshd_test_output {
    my ( $self, $output ) = @_;
    if ( defined $output ) {
        $self->{_sshd_test_output} = $output;
    }
    return $self->{_sshd_test_output};
}

=item notify_failure($application)

Method to send an iContact notification with the details of the last
configuration cahnge failrue.

=cut

sub notify_failure {
    my $self = shift;
    Cpanel::LoadModule::load_perl_module("Cpanel::Notify");
    return Cpanel::Notify::notification_class(
        'class'            => 'SSHD::ConfigError',
        'application'      => 'SSHD::Config',
        'constructor_args' => [
            syntax_error => $self->sshd_test_output(),
            diff         => $self->current_diff(),
            filename     => $self->filename(),
        ]
    );
}

sub _test_sshd_conf {
    my ( $self, $test_filename ) = @_;
    Cpanel::LoadModule::load_perl_module("Cpanel::SafeRun::Errors");
    $self->sshd_test_output( scalar Cpanel::SafeRun::Errors::saferunallerrors( $self->_sshd_binary, '-t', '-f', $test_filename ) );
    return ( $? == 0 );
}

sub _sshd_binary {
    my $self = shift;
    unless ( defined $self->{_sshd_binary} ) {
        Cpanel::LoadModule::load_perl_module("Cpanel::FindBin");
        $self->{_sshd_binary} = Cpanel::FindBin::findbin( 'sshd', 'path' => [qw{ /sbin /usr/sbin /usr/local/sbin /bin /usr/bin /usr/local/bin /usr/local/cpanel/3rdparty/bin }] );
    }
    return $self->{_sshd_binary};
}

sub _transaction {
    my $self = shift;
    return $self->{transaction} if defined $self->{transaction};
    return $self->_open_rw();
}

sub _open_ro {
    my $self = shift;
    return $self->_open_transaction_object('Cpanel::Transaction::File::RawReader');
}

sub _open_rw {
    my $self = shift;
    return $self->_open_transaction_object('Cpanel::Transaction::File::Raw');
}

sub _open_transaction_object {
    my ( $self, $module ) = @_;
    Cpanel::LoadModule::load_perl_module($module);
    my $file        = $self->filename();
    my $permissions = $self->permissions();
    try {
        $self->{transaction} = "$module"->new( 'path' => $file, 'permissions' => $permissions, 'restore_original_permissions' => 1 );
    }
    catch {
        my $ex          = $_;
        my $msg         = "Failed to open “$file”: " . Cpanel::Exception::get_string($_);
        my $log_message = "Failed to open “$file”: $ex";
        Cpanel::Debug::log_info($log_message);
        die $msg;
    };

    return $self->{transaction};
}

=back

=cut

1;

__END__

Settings with Multiple Values:

ListenAddress
Port
HostKey
AcceptEnv
