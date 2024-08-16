package Cpanel::AdvConfig::dovecot::Includes;

# cpanel - Cpanel/AdvConfig/dovecot/Includes.pm          Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use cPstrict;

use Cpanel::Exception                 ();
use Cpanel::Logger                    ();
use Cpanel::SafeRun::Errors           ();
use Cpanel::SafeDir::MK               ();
use Cpanel::AdvConfig::dovecot::utils ();
use Cpanel::FileUtils::Copy           ();
use Cpanel::ConfigFiles               ();
use Cpanel::Context                   ();
use Cpanel::Rand::Get                 ();
use Cpanel::Template::Files           ();
use Cpanel::FileUtils::Lines          ();
use Cpanel::Time::ISO                 ();
use Cpanel::AdvConfig                 ();
use Cpanel::Rand                      ();

use Try::Tiny;

our $VERSION = '2.0';

our $_TEMPLATES_SOURCE_DIR = "$Cpanel::ConfigFiles::CPANEL_ROOT/src/templates";
our $_TEMPLATES_TARGET_DIR = '/var/cpanel/templates';

my $logger;

=encoding utf-8

=head1 NAME

Cpanel::AdvConfig::dovecot::Includes

=head1 DESCRIPTION

This module is intended to be used as a base class for adding dovecot configuration includes.

=head1 METHODS

=head2 new()

Constructor.

Arguments as a hash ref.

=over

=item * service - String - ( Required ) The name of the service we are making an include for.

=item * conf_file - String - ( Required ) The full path of the configuration file that will be
included into the main dovecot config.

=item * verify_checks - ArrayRef - ( Optional ) An array reference of regular expressions that will
be checked against the configuration file to ensure it is valid.

=item * logger - Object - ( Optional ) A Cpanel::Logger object.

=back

=cut

sub new ( $pkg, $args ) {

    foreach my $arg ( 'service', 'conf_file' ) {
        die Cpanel::Exception->create_raw("You must define $arg.") if !$args->{$arg};
    }

    my $self = {
        service       => $args->{service},
        verify_checks => $args->{verify_checks},
        conf_file     => $args->{conf_file},
    };

    $self->{logger} = $args->{logger} // _logger();

    bless $self, $pkg;
    return $self;
}

=head2 get_config()

The get_config method must be implemented by consumers of this class.

It should return a hash_ref of values to be applied to the config template.

see Cpanel::AdvConfig::dovecotSSL and Cpanel::AdvConfig::dovecotSNI for examples.

=cut

sub get_config {
    die Cpanel::Exception->create_raw("You must implement the 'get_config' method.");
}

=head2 check_syntax()

Runs the specified config through the dovecot binary to check for syntax errors.

Returns true or false.

In array context, returns the response from the dovecot binary.

=over

=item * dovecot_conf - String - ( Required ) The file path to the configuration to be checked.

=back

=cut

sub check_syntax ( $self, $dovecot_conf ) {

    my $dovecot_bin = Cpanel::AdvConfig::dovecot::utils::find_dovecot_bin();
    unless ( -e $dovecot_conf ) {
        return wantarray ? ( 0, $dovecot_conf . ' is missing!' ) : 0;
    }
    unless ( -x $dovecot_bin ) {
        return wantarray ? ( 0, $dovecot_bin . ' is missing or not executable!' ) : 0;
    }

    my $response = Cpanel::SafeRun::Errors::saferunallerrors( $dovecot_bin, '-c', $dovecot_conf, '-n' );
    my $valid    = $response !~ /^Fatal: Invalid configuration/s;
    return wantarray ? ( $valid, $response ) : $valid;
}

=head2 check_if_config_file_is_valid

Checks the supplied configuration file for validity. Applies the regular expressions in
the 'verify_checks' attribute to the configuration file.

Returns true or false.

=over

=item * file - String - ( Required ) The file path to the configuration to be checked.

=back

=cut

sub check_if_config_file_is_valid ( $self, $file ) {

    return 1 if try { $self->_verify_that_config_file_is_valid($file); 1 };

    return 0;
}

sub _verify_that_config_file_is_valid ( $self, $file ) {

    foreach my $str ( @{ $self->{verify_checks} } ) {
        if ( !Cpanel::FileUtils::Lines::has_txt_in_file( $file, $str ) ) {
            die "Configuration file did not match \'$str\'!\n";
        }
    }
    return;
}

=head2 get_template_file()

Returns the service template file.

Returns ( $template_file_or_0, $undef_or_error ) as per Cpanel::Template::Files::get_service_template_file

=cut

sub get_template_file ($self) {

    Cpanel::Context::must_be_list();
    return Cpanel::Template::Files::get_service_template_file( $self->{service}, 0, 'main' );
}

=head2 check_if_local_template_is_valid()

Checks the local template for validity.

This method looks for local configurations. If found it is sent to check_if_config_file_is_valid().

Returns true or false.

=over

=item * template_file - String - ( Optional ) File path to the template file to check.

=back

=cut

sub check_if_local_template_is_valid ( $self, $template_file = undef ) {

    my $error;
    ( $template_file, $error ) = $self->get_template_file() if !$template_file;

    if ( !$template_file ) {
        die Cpanel::Exception->create_raw("The dovecot template could not be retrieved due to an error: $error");
    }

    # if we don't have a local config the local config is a-ok as we'll use the default instead.
    return 1 if $template_file !~ /\.local$/;

    # Currently we're only checking for one bit of text, but if we expand this.. please do something more efficient
    return $self->check_if_config_file_is_valid($template_file);
}

=head2 update_templates()

Updates the service template.

Returns true or false if the templates was updated or not.

=over

=item * versioned_service - String - ( Optional ) The name of the service to update, defaults to the service attribute.

=back

=cut

sub update_templates ( $self, $versioned_service = undef ) {

    $versioned_service //= $self->{service};

    die "service not specified...can't determine location of templates" if !$versioned_service;

    #TODO: safemkdir() actually does the recursive mkdir() for us;
    #it shouldn’t be necessary to write it out here manually.
    foreach my $dir ( $_TEMPLATES_TARGET_DIR, "$_TEMPLATES_TARGET_DIR/$versioned_service" ) {
        Cpanel::SafeDir::MK::safemkdir( $dir, '0755' ) unless ( -d $dir );
    }

    my $system_template = "$_TEMPLATES_SOURCE_DIR/$versioned_service/main.default";
    unless ( -e $system_template ) {
        Cpanel::Logger::logger(
            {
                'message'   => "Can't locate cPanel-supplied template for $versioned_service.  Is this a new unsupported version?",
                'level'     => 'warn',
                'service'   => __PACKAGE__,
                'output'    => 0,
                'backtrace' => 0,
            }
        );
    }
    my $system_mtime = ( stat($system_template) )[9];

    my $target_template = "$_TEMPLATES_TARGET_DIR/$versioned_service/main.default";

    if ( -e $target_template ) {
        my $target_mtime = ( stat($target_template) )[9];

        my $why_replace;
        my $short_why;

        if ( $target_mtime <= $system_mtime ) {
            $why_replace = "This system’s custom Dovecot configuration appears to be older than the cPanel-supplied configuration.";
            $short_why   = 'outdated';
        }
        elsif ( $target_mtime > time ) {
            $why_replace = sprintf( "This system’s custom Dovecot configuration has a last-modified time that is in the future (%s).", Cpanel::Time::ISO::unix2iso($target_mtime) );
            $short_why   = 'timewarp';
        }
        else {
            try {
                $self->_verify_that_config_file_is_valid($target_template);
            }
            catch {
                chomp;
                $why_replace = "This system’s custom Dovecot configuration is invalid. ($_)";
                $short_why   = 'invalid';
            };
        }

        if ($why_replace) {
            my $rename_to = join '.', $target_template, $short_why, Cpanel::Time::ISO::unix2iso(), Cpanel::Rand::Get::getranddata( 8, [ 0 .. 9 ] );

            warn "$why_replace The system will rename the custom configuration to “$rename_to” and install a default configuration.\n";

            rename $target_template, $rename_to or do {
                warn "The system failed to rename “$target_template” to “$rename_to” because of an error: $!";

                #I guess just clobber here? Better that, probably,
                #than for Dovecot to stay broken.
            };
        }
        else {
            return 0;
        }
    }

    Cpanel::FileUtils::Copy::safecopy( $system_template, $target_template );

    chmod oct(644), $target_template;

    return 1;
}

=head2 rebuild_conf()

Rebuilds the configuration file based on the template.

Returns true or false if the rebuild was successful or not.

=cut

sub rebuild_conf ($self) {

    my $dovecot_conf      = $self->{conf_file};
    my $test_dovecot_conf = Cpanel::Rand::get_tmp_file_by_name($dovecot_conf);

    return if ( $test_dovecot_conf eq '/dev/null' );

    chmod( 0644, $test_dovecot_conf ) or do {
        warn "chmod($test_dovecot_conf) failed: $!";
        return;
    };

    my ( $returnval, $message ) = Cpanel::AdvConfig::generate_config_file( { 'service' => $self->{service}, 'force' => 0, '_target_conf_file' => $test_dovecot_conf } );
    if ( !$returnval ) {
        unlink $test_dovecot_conf;
        warn "dovecot generate_config_file error: $message";
        return;
    }

    rename $test_dovecot_conf, $dovecot_conf or do {
        warn "rename($test_dovecot_conf => $dovecot_conf) failed: $!";
    };

    unlink $dovecot_conf . '.datastore';    # Just in case
    return 1;
}

sub _logger {
    return $logger //= Cpanel::Logger->new();
}

1;
