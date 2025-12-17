#! /usr/bin/env perl

##########################################################################
#
# FILE:   update_db.pl
# USAGE:  update_db.pl --database <databasename> --host <host>
#                      --password <password> --user <username>
#
# DESCRIPTION:  Updates the cw_overview and cw_overview_errors database
#               tables for Checkwiki.  Tables contain a list of current
#               errors found and how many have been fixed (done).
#               Tables are used by update_html.pl to for webpages.
#
#               cw_overview_errors contains data for most webpages.
#               cw_overview contains data for main index.html page.
#
# AUTHOR:  Stefan Kühn, Bryan White
# VERSION: 2017-01-06
# LICENSE: GPLv3
#
##########################################################################

use strict;
use warnings;
use feature 'unicode_strings';

use DBI;
use DBD::mysql;
use Getopt::Long
  qw(GetOptionsFromString :config bundling no_auto_abbrev no_ignore_case);

my $dbh;
my @projects;

my $time_start_script = time();
my $time_start;

########################################################
## GET OPTIONS
########################################################

my ( $DbName, $DbServer, $DbUsername, $DbPassword, $config_name );

GetOptions(
    'database|d=s' => \$DbName,
    'host|h=s'     => \$DbServer,
    'password=s'   => \$DbPassword,
    'user|u=s'     => \$DbUsername,
    'config|c=s'   => \$config_name
);

if ( defined $config_name ) {
    open( my $file, '<:encoding(UTF-8)', $config_name )
      or die 'Could not open file ' . $config_name . "\n";
    while ( my $line = <$file> ) {
        chomp($line);
        my @words = ( split / /, $line );
        $DbName     = $words[1] if ( $words[0] =~ /--database/ );
        $DbUsername = $words[1] if ( $words[0] =~ /--user/ );
        $DbPassword = $words[1] if ( $words[0] =~ /--password/ );
        $DbServer   = $words[1] if ( $words[0] =~ /--host/ );
    }
    close($file)
      or die 'Could not close file ' . $config_name . "\n";
}
else {
    die("No config file entered, for example: -c checkwiki.cfg\n");
}

##########################################################################
## MAIN PROGRAM
##########################################################################

open_db();
get_projects();

cw_overview_errors_update_done();
cw_overview_errors_update_error_number();

cw_overview_update_done();
cw_overview_update_error_number();
cw_overview_update_last_update();

close_db();
output_duration_script();

##########################################################################
## OPEN DATABASE
##########################################################################

sub open_db {

    $dbh = DBI->connect(
        'DBI:mysql:'
          . $DbName
          . ( defined($DbServer) ? ':host=' . $DbServer : q{} ),
        $DbUsername,
        $DbPassword,
        {
            mysql_enable_utf8 => 1
        }
    ) or die("Could not connect to database:  DBI::errstr() \n");

	$dbh->do('SET NAMES utf8mb4')
	   or die($dbh->errstr);

    return ();
}

###########################################################################
## CLOSE DATABASE
###########################################################################

sub close_db {
    $dbh->disconnect();

    return ();
}

###########################################################################
## GET PROJECT NAMES FROM DATABASE (ie enwiki, dewiki)
###########################################################################

sub get_projects {
    my $project_counter = 0;
    my $result          = q();

    print "Load projects from db\n";

    my $sth = $dbh->prepare('SELECT id FROM cw_overview ORDER BY project;')
      or die "Can not prepare statement: $DBI::errstr\n";
    $sth->execute
      or die "Cannot execute: $sth->errstr\n";

    my $project_sql;
    $sth->bind_col( 1, \$project_sql );

    while ( $sth->fetchrow_arrayref ) {
        push( @projects, $project_sql );
        $project_counter++;
    }

    return ();
}

###########################################################################
## UPDATE THE NUMBER OF ARTICLES THAT HAVE BEEN DONE
###########################################################################

sub cw_overview_errors_update_done {
    $time_start = time();

    print "Group and count the done in cw_error -> update cw_overview_error\n";

    foreach my $project (@projects) {

        my $sth = $dbh->prepare(
            q{UPDATE cw_overview_errors, (
            SELECT a.projectno, a.id , b.done FROM cw_overview_errors a
            LEFT OUTER JOIN (
            SELECT COUNT(*) done , error id , projectno
            FROM cw_error WHERE ok = 1 AND projectno = ? 
            GROUP BY projectno, error
            ) b
            ON a.projectno = b.projectno AND a.projectno = ? 
            AND a.id = b.id
            ) basis
            SET cw_overview_errors.done = basis.done
            WHERE cw_overview_errors.projectno = basis.projectno
            AND cw_overview_errors.projectno = ? 
            AND cw_overview_errors.id = basis.id
          ;}
        ) or die "Can not prepare statement: $DBI::errstr\n";
        $sth->execute( $project, $project, $project )
          or die "Cannot execute: $sth->errstr\n";
    }

    output_duration();

    return ();
}

###########################################################################
## UPDATE THE NUMBER OF ERRORS CURRENTLY IN ARTICLES
###########################################################################

sub cw_overview_errors_update_error_number {
    $time_start = time();

    print "Group and count the error in cw_error -> update cw_overview_error\n";

    foreach my $project (@projects) {

        my $sth = $dbh->prepare(
            q{UPDATE cw_overview_errors, (
            SELECT a.projectno, a.id, b.errors errors  
            FROM cw_overview_errors a
            LEFT OUTER JOIN (
            SELECT COUNT( *) errors, error id , projectno
            FROM cw_error 
            WHERE ok = 0
            AND projectno = ? 
            GROUP BY projectno, error
            ) b
            ON a.projectno = b.projectno
            AND a.projectno = ? 
            AND a.id = b.id
            ) basis
            SET cw_overview_errors.errors = basis.errors
            WHERE cw_overview_errors.projectno = basis.projectno
            AND cw_overview_errors.projectno = ? 
            AND cw_overview_errors.id = basis.id
          ;} )
          or die "Can not prepare statement: $DBI::errstr\n";
        $sth->execute( $project, $project, $project )
          or die "Cannot execute: $sth->errstr\n";
    }

    output_duration();

    return ();
}

###########################################################################
## UPDATE THE NUMBER OF ERRORS CURRENTLY IN ARTICLES
###########################################################################

sub cw_overview_update_done {
    $time_start = time();

    print "Sum done article in cw_overview_errors --> update cw_overview\n";

    my $sth = $dbh->prepare (
        q{UPDATE cw_overview, (
        SELECT IFNULL(sum(done),0) done, projectno
        FROM cw_overview_errors GROUP BY projectno
        ) basis
        SET cw_overview.done = basis.done
         WHERE cw_overview.id = basis.projectno
      ;} )
      or die "Can not prepare statement: $DBI::errstr\n";
    $sth->execute
      or die "Cannot execute: $sth->errstr\n";

    output_duration();

    return ();
}

###########################################################################
## UPDATE THE NUMBER OF ERRORS CURRENTLY IN ARTICLES
###########################################################################

sub cw_overview_update_error_number {
    $time_start = time();

    print "Sum errors in cw_overview_errors --> update cw_overview\n";

    my $sth = $dbh->prepare(
        q{ update cw_overview, (
        SELECT IFNULL(sum(errors),0) errors, projectno
        FROM cw_overview_errors GROUP BY projectno
        ) basis
        SET cw_overview.errors = basis.errors
        WHERE cw_overview.id = basis.projectno
      ;} )
      or die "Can not prepare statement: $DBI::errstr\n";
    $sth->execute
      or die "Cannot execute: $sth->errstr\n";

    output_duration();

    return ();
}

###########################################################################
## UPDATE THE TIME THIS PROGRAM LAST RUN
###########################################################################

sub cw_overview_update_last_update {
    $time_start = time();

    print "Update last_update\n";

    foreach my $project (@projects) {

        my $sth = $dbh->prepare(
            q{-- update last_update
            UPDATE cw_overview, (SELECT max(found) found, project
            FROM cw_error WHERE project = ?
            ) basis
            SET cw_overview.last_update = basis.found
            WHERE cw_overview.project = basis.project
          ;} )
          or die "Can not prepare statement: $DBI::errstr\n";
        $sth->execute($project)
          or die "Cannot execute: $sth->errstr\n";
    }

    output_duration();

    return ();
}

###########################################################################
##
###########################################################################

sub cw_overview_update_last_change {

    print "Update change\n";

    $time_start = time();

    foreach my $project (@projects) {

        my $sth = $dbh->prepare(
            q{-- UPATE last_dump
            UPDATE cw_overview, (
            SELECT a.project project, c.errors last, b.errors one, a.errors, a.errors-b.errors diff1, a.errors-c.errors diff7
            FROM (
            SELECT project, IFNULL(errors,0) errors FROM cw_statistic_all 
            WHERE DATEDIFF(now(),daytime) = 0
            AND project = ? 
            ) a JOIN 
            (
            SELECT project, IFNULL(errors,0) errors 
            FROM cw_statistic_all 
            WHERE DATEDIFF(now(),daytime) = 1
            AND project = ? 
            ) b
            ON (a.project = b.project)
            JOIN 
            (SELECT project, ifnull(errors,0) errors FROM cw_statistic_all 
            WHERE DATEDIFF(now(),daytime) = 7
            AND project = ? 
            ) c
            ON (a.project = c.project)
            ) basis
            SET cw_overview.diff_1 = basis.diff1, 
            cw_overview.diff_7 = basis.diff7
            WHERE cw_overview.project = basis.project
            AND cw_overview.project = ?
          ;} )
          or die "Can not prepare statement: $DBI::errstr\n";
        $sth->execute
          or die "Cannot execute: $sth->errstr\n";
    }

    output_duration();

    return ();
}

###########################################################################
## SUBROUTINES TO DETERMINE HOW LONG A SUB OR THE PROGRAM RAN
###########################################################################

sub output_duration {
    my $time_end         = time();
    my $duration         = $time_end - $time_start;
    my $duration_minutes = int( $duration / 60 );
    my $duration_secounds =
      int( ( ( int( 100 * ( $duration / 60 ) ) / 100 ) - $duration_minutes ) *
          60 );

    print "Duration:\t"
      . $duration_minutes
      . ' minutes '
      . $duration_secounds
      . " secounds\n\n";

    return ();
}

sub output_duration_script {
    my $time_end         = time();
    my $duration         = $time_end - $time_start_script;
    my $duration_minutes = int( $duration / 60 );
    my $duration_secounds =
      int( ( ( int( 100 * ( $duration / 60 ) ) / 100 ) - $duration_minutes ) *
          60 );

    print "Duration of script:\t"
      . $duration_minutes
      . ' minutes '
      . $duration_secounds
      . " secounds\n";

    return ();
}