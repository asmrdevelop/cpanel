package Whostmgr::API::1::Data::Wrapper;

# cpanel - Whostmgr/API/1/Data/Wrapper.pm          Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use strict;
use Try::Tiny;

use Whostmgr::API::1::Data::Columns ();
use Whostmgr::API::1::Data::Chunk   ();
use Whostmgr::API::1::Data::Filter  ();
use Whostmgr::API::1::Data::Sort    ();
use Whostmgr::API::1::Data::Args    ();

use Whostmgr::API::1::Utils::Metadata ();    ## PPI NO PARSE - bless()ed

=encoding utf-8

=head1 NAME

Whostmgr::API::1::Data::Wrapper

=head1 SUBROUTINES

=head2 apply()

=head3 Purpose

This method applies the filter, sort and chunk system to the passed in data the same way the JSON-XML API
performs this process. This allows the data to be pre-fetched in whostmgr* files and JSON serialized to the
same format that remote API calls. The justification is that client code can process the data the same way
irregardless if its remote retrieved or if its pre-fetched.

=head3 Arguments

  - 'api_args' - Request meta data in deserialized format.
  - 'data' - Hash - Containing one set of data to be post processed with filtering, sorting and paging based
    on the passed in request_meta argument.
  - 'result' - Hash :

=head3 Returns

  - 'result' - Hash - Containing the following:

=head3 Example

=cut

sub apply {

    my ( $api_args, $data, $result ) = @_;
    my $records;

    # Records eligible for filtering, sorting, and pagination are returned by the
    # underlying API layer as a value within the 'data' hash. If there is more than
    # one key/value pair in the data section, the choice of which records to process
    # is ambiguous, leading to broken API data sorting, filtering, and pagination.
    # However, if the metadata supplied by the API function provides a hint in the
    # 'payload_name' field as to which field within data should be processed, it will be
    # honored.
    if ( my $payload_name = delete $result->{'metadata'}{'payload_name'} ) {
        ($records) = $data->{$payload_name};
    }

    # If no hint is provided, the unpredictable and buggy backward-compatible behavior
    # will remain in effect.
    else {
        ($records) = values %$data;
    }

    # Data returned by the underlying API layer is returned as
    # a hash reference with a single key indicating the schema name
    # of the records and the records as the value.
    Whostmgr::API::1::Data::Columns::apply( $api_args->{'columns'}, $records, $result->{'metadata'} ) if $api_args->{'columns'}{'enable'};
    Whostmgr::API::1::Data::Filter::apply( $api_args->{'filter'}, $records, $result->{'metadata'} )   if $api_args->{'filter'}{'enable'};
    Whostmgr::API::1::Data::Sort::apply( $api_args->{'sort'}, $records, $result->{'metadata'} )       if $api_args->{'sort'}{'enable'};
    Whostmgr::API::1::Data::Chunk::apply( $api_args->{'chunk'}, $records, $result->{'metadata'} )     if $api_args->{'chunk'}{'enable'};

    # Stash the data in the results
    $result->{'data'} = $data;

    return $result;
}

=head2 execute()

=head3 Purpose

This is a general purpose tool to call a code block and process the returned data for pre-fetch
in whostmgr* file. It builds a set of default parameters, merges those with the ones passed on
the request, calls the code and finally applies the filter, sort and chunk system to the data the
same way the JSON-XML API performs this process.

=head3 Arguments

  - 'defaults' - Hash - Argument to pass to Whostmgr::API::1::Data::Args::build_api_args.
  - 'formref'  - Hash - Form data passed from the caller.
  - 'coderef'  - Sub  - Reference to a sub routine to call.

=head3 Returns

  - 'result' - Hash - Containing the following:
  - 'data' - Array - The adjusted dataset.
  - 'metadata' - Hash - The metadata for the post processing.
  - 'useform'  - Boolean - Use the form data to get api arguments. Defaults to truem

=head3 Example

=cut

sub execute {
    my ( $defaults, $formref, $coderef, $useform, $output_coderef ) = @_;
    my $api_args;

    if ( !defined($useform) ) {
        $useform = 1;
    }

    $api_args = Whostmgr::API::1::Data::Args::build_api_args($defaults);

    if ($useform) {
        my $form_api_args = Whostmgr::API::1::Data::Args::extract_api_args($formref);
        for my $postprocess_type (qw(sort chunk filter)) {
            if ( 'HASH' eq ref $form_api_args->{$postprocess_type} && %{ $form_api_args->{$postprocess_type} } ) {
                $api_args->{$postprocess_type} = $form_api_args->{$postprocess_type};
            }
        }
    }

    my $result = build_result( undef, "Direct", $api_args );

    execute_internal( $coderef, $formref, $api_args, $result, $output_coderef );

    return $result;
}

=head2 build_result()

=head3 Purpose

Build an initialized result based on the passed in data.

=head3 Arguments

  - 'namespace' - String|undef - For dynamically loaded modules, the namespace after "Whostmgr::API::1::". For everything else, undef.
  - 'app'       - String       - Name of the method
  - 'api_args'  - Hash         - Api specific arguments.

=head3 Returns

A hash reference that contains:

=over

=item - 'metadata' - A L<Whostmgr::API::1::Utils::Metadata> instance.

This class’s object
internals are, for historical reasons, documented as a de facto internal API.
It is a hash reference that contains:

=over

=item - 'command' - String - Name of the command.

=item - 'version' - Number - API version.

=item - 'result'  - Boolean - 0 for failure, 1 for success

=item - 'reason'  - String - Description of the error

=back

=back

=cut

sub build_result {
    my ( $namespace, $app, $api_args ) = @_;

    my %metadata = (
        $namespace ? ( 'namespace' => $namespace ) : (),
        'command' => $app,
        'version' => $api_args->{'version'} || 1,
        'result'  => 0,
        'reason'  => 'Unknown error.',
    );

    return {
        'metadata' => bless( \%metadata, 'Whostmgr::API::1::Utils::Metadata' ),
    };
}

=head2 execute_internal()

=head3 Purpose

Execute the passed in code reference in the requested context.

=head3 Arguments

=over

=item - 'coderef'      - Code - Subroutine to call.

=item - 'command_args' - Hash   - Call specific arguments.

=item - 'api_args'     - Hash   - Common API specific arguments.

=item - 'result'       - Hash - Containing the following:

=over

=item - 'metadata' - A L<Whostmgr::API::1::Utils::Metadata> instance.

=item - 'command' - String - Name of the command.

=item - 'version' - Number - API version.

=item - 'result'  - Boolean - 0 for failure, 1 for success

=item - 'reason'  - String - Description of the error

=back

=back

=head3 Returns

Upon return the result is more fully filled with data and metadata depending the contents of the request,
the code that runs and the post processing that follows.

=cut

sub execute_internal {
    my ( $coderef, $command_args, $api_args, $result, $output_coderef ) = @_;

    try {
        my $data = $coderef->( $result->{'metadata'}, $command_args, $api_args, $output_coderef );

        if ( 'HASH' eq ref $data ) {

            # Apply the sort, filter and paginate
            apply( $api_args, $data, $result );
        }

        # Generally, this shouldn't happen.  If it does, it most likely
        # indicates a failure on the part of the API implementer.
        elsif ( defined $data ) {
            $result->{'metadata'}{'result'} = 0;
            $result->{'metadata'}{'reason'} = 'Invalid API data format.';
        }
    }
    catch {
        my $err_str = UNIVERSAL::isa( $_, 'Cpanel::Exception' ) ? $_->to_string() : $_;
        $result->{'metadata'}{'result'} = 0;
        $result->{'metadata'}{'reason'} = 'API failure: ' . $err_str;
    };

    return 1;
}

1;
