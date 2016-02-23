=================
Data organization
=================

Exploring the Godzilla server
-----------------------------

Once data is collected, it's sent to the KKI Godzilla server for permanent
storage. The first step in analysis then is to retrieve the data from Godzilla.
Like our lab server, Godzilla is a UNIX machine, so we will use standard
command line tools to log onto the server and transfer data.

To log onto the server, you need to contact system administrator at KKI and
request an account. When you have an account, you can log on using ``ssh`` and
begin exploring.

To simplify the log-in process, you should set up public key authentication.
For a description of what this is and how to do it, see `this tutorial`_.

Once you're logged in, navigate to /g4/mbedny. This is our lab folder on
Godzilla. All of our studies are stored in this folder (e.g. BSYN, BRAILLE).
Within each study folder, there will be a folder for each subject. And within
each subject's folder, a par and rec file for each collected run, plus
an MR folder, containing DICOM images for the MPRAGE scan::

  /g4/mbedby/
    |- BSYN/
      |- BSYN_S_01/
        |- bsyn_s_01_3_1.par
        |- bsyn_s_01_3_1.rec
        |- bsyn_s_01_4_1.par
        |- bsyn_s_01_4_1.rec
      |- BSYN_S_02/
    |- BRAILLE1/
      |- BRAILLE1_CB_01
        |- MR/
          |- 1.3.46.670589.11.24058.5.0.1788.2014053014171806001
          |- 1.3.46.670589.11.24058.5.0.1788.2014053014171865002
        |- braille1_cb_01_3_1.par
        |- braille1_cb_01_3_1.rec

Typically, runs 1, 2 are the survey and reference scans respectively. These
scans are not usually sent to Godzilla during data collection. The first scan
we keep is usually run 3, the MPRAGE.

The scan log
------------

For each scanning session you must keep a scan log documenting the events of
the session. The scan log is how we associate scanner runs with behavioral
files. Without the scan logs we could not run any analyses.

You should keep both a written scan log and an electronic version. The format
for the electronic version is as follows::

  # Study: BSYN
  # Subject ID: BSYN_S_01
  # Scanner ID: BSYN_04
  # Registration ID: 1403250900
  # Date: 3/25/14 9:00
  # Scanner: MR1 32ch
  # Scanned by: TB
  
  3 mprage
  4 bsyn_01
  5 bsyn_02
  6 bsyn_03
  7 bsyn_04 # participant got out to use the restroom.
  8 bsyn_05
  9 bsyn_06

  # Notes:
  # - Volume set to 2.5
  # - Good performance on average
  # - Subject a little claustrophobic for the first scan

The scan log starts with a header containing info about the scan session: the
study name, the subject ID, the scanner subject ID (which may or may not be
different), etc. 

- Each line of the header must start with "#".
- The "key" for each line must be spelled exactly as shown.
- The keys must be separated from their values with a colon.

The next section of the scan log is a two-column matrix consisting of run
number, run name pairs. The run number is the number of the scan, as it was
collected. The run name typically has the format ``{task}_{run num}``, with the
run number being zero-padded to two places.

Last, there is an optional *Notes* section, where you can record miscellaneous
information about the session or the participant. Each line of notes should
start with "#".

Transferring data for analysis
------------------------------

Transferring data is a three part process: 

1. Fetch the par and rec files from Godzilla.
2. Convert the par/recs to gzipped Nifti files.
3. Rename the converted files to something more convenient than the default
   scanner names.

All of these steps are accomplished with the ``parfetch`` command, which is
part of the lab's suite of scripts ::

  Usage: parfetch [options] <scan-log>

  Fetch par and rec files from the scanner file server and convert
  to gzipped nifti. File organization on the server is assumed to
  follow the convention:

    {lab dir}/{study dir}/{subject ID}/*_{run #}_{acq #}.*

  Arguments:
    <scan-log>   Scan log text file. Describes how files should be
                 renamed. First column is run number, second column
                 is new name. You may optionally specify the Study,
                 Subject ID, and/or Scanner ID in a comment line
                 (starting with #). All other lines starting with #
                 will be ignored. See below for an example of the
                 proper format.

  Options:
    --study <study>     Name of study on server. Read from the scan log
                        by default (needs a '# Study: XXXX' line).
    --sub <scan-sub>    Scanner subject ID on server. Read from the scan
                        log by default (needs a '# Scanner ID: XXXX' line).
    --out <outdir>      Directory to put converted data. If this option
                        is not specified, the converted data will be placed
                        in {subject ID}/raw, in the working directory,
                        where {subject ID} is read from the scan log.
    --u <user>          Name of server user [default: clane9].
    --labdir <dir>      Lab directory on server [default: /g4/mbedny].
    --no-clean          Don't delete redundant rec files. 

First ``parfetch`` reads the scan log for the scan session to determine where
the data is located on Godzilla, and where it should be placed on the lab
server. It uses the "Study" and "Scanner ID" values to determine where the data
is located, and it uses the "Subject ID" value to decide where to put the data
(defaulting to ``{Subject ID}/raw`` in the working directory.

Next, the command transfers the data to the lab server using the ``scp``
command. For this part to work it is essential that you can access Godzilla.
And if you have public-key authentication set up, you won't have to enter your
password. Next, ``parfetch`` uses ``dcm2nii`` to convert the data to gzipped
Nifti files. See the Mricron_ site for details on this part. Last, ``parfetch``
renames the converted files according to the names given in the second column
in the scan log.

If we were to run ``parfetch`` on the example scan log above, the resulting raw
folder would be structured like this::

  BSYN_S_01/
    |- raw/
      |- bsyn_01.nii.gz
      |- bsyn_02.nii.gz
      |- mprage.nii.gz
      |- par/
        |- bsyn_04_3_1.par
        |- bsyn_04_4_1.par
        |- MR/
      |- parfetch.log
      |- sl.txt

.. _this tutorial: https://macnugget.org/projects/publickeys/
.. _Mricron: http://www.mccauslandcenter.sc.edu/mricro/mricron/dcm2nii.html
