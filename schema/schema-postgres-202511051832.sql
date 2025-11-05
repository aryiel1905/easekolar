--
-- PostgreSQL database dump
--

\restrict tUgg4wODR27grrtYiJjpdrB8dffVuWvdfjEhCF46QFMZFq7xNPFxSQ0JProlhpo

-- Dumped from database version 17.6
-- Dumped by pg_dump version 18.0

-- Started on 2025-11-05 18:32:59

SET statement_timeout = 0;
SET lock_timeout = 0;
SET idle_in_transaction_session_timeout = 0;
SET transaction_timeout = 0;
SET client_encoding = 'UTF8';
SET standard_conforming_strings = on;
SELECT pg_catalog.set_config('search_path', '', false);
SET check_function_bodies = false;
SET xmloption = content;
SET client_min_messages = warning;
SET row_security = off;

--
-- TOC entry 48 (class 2615 OID 2200)
-- Name: public; Type: SCHEMA; Schema: -; Owner: pg_database_owner
--

CREATE SCHEMA public;


ALTER SCHEMA public OWNER TO pg_database_owner;

--
-- TOC entry 3811 (class 0 OID 0)
-- Dependencies: 48
-- Name: SCHEMA public; Type: COMMENT; Schema: -; Owner: pg_database_owner
--

COMMENT ON SCHEMA public IS 'standard public schema';


--
-- TOC entry 456 (class 1255 OID 17968)
-- Name: copy_to_campus_table(); Type: FUNCTION; Schema: public; Owner: postgres
--

CREATE FUNCTION public.copy_to_campus_table() RETURNS trigger
    LANGUAGE plpgsql
    AS $$
BEGIN
  IF NEW.campus = 'PRMSU Castillejos' THEN
    INSERT INTO applicants_castillejos SELECT NEW.*;
  ELSIF NEW.campus = 'PRMSU Iba' THEN
    INSERT INTO applicants_iba SELECT NEW.*;
  ELSIF NEW.campus = 'PRMSU Masinloc' THEN
    INSERT INTO applicants_masinloc SELECT NEW.*;
  ELSIF NEW.campus = 'PRMSU San Marcelino' THEN
    INSERT INTO applicants_sanmarcelino SELECT NEW.*;
  ELSIF NEW.campus = 'PRMSU Candelaria' THEN
    INSERT INTO applicants_candelaria SELECT NEW.*;
  ELSIF NEW.campus = 'PRMSU Sta. Cruz' THEN
    INSERT INTO applicants_stacruz SELECT NEW.*;
  END IF;
  RETURN NEW;
END;
$$;


ALTER FUNCTION public.copy_to_campus_table() OWNER TO postgres;

--
-- TOC entry 457 (class 1255 OID 43156)
-- Name: normalize_phone_ph(text); Type: FUNCTION; Schema: public; Owner: postgres
--

CREATE FUNCTION public.normalize_phone_ph(p text) RETURNS text
    LANGUAGE plpgsql
    AS $$
DECLARE
  d text;
BEGIN
  IF p IS NULL THEN RETURN NULL; END IF;
  -- Keep + and digits first pass
  d := regexp_replace(p, '[^0-9+]', '', 'g');

  -- Already E.164
  IF left(d,1) = '+' THEN RETURN d; END IF;

  -- Digits only
  d := regexp_replace(d, '[^0-9]', '', 'g');

  -- 09XXXXXXXXX -> +639XXXXXXXXX
  IF left(d,2) = '09' AND length(d) = 11 THEN
    RETURN '+63' || substr(d,2);
  -- 9XXXXXXXXX -> +639XXXXXXXXX
  ELSIF left(d,1) = '9' AND length(d) = 10 THEN
    RETURN '+63' || d;
  -- 639XXXXXXXXX -> +639XXXXXXXXX
  ELSIF left(d,3) = '639' AND length(d) = 12 THEN
    RETURN '+' || d;
  ELSE
    RETURN NULL; -- not recognized
  END IF;
END;
$$;


ALTER FUNCTION public.normalize_phone_ph(p text) OWNER TO postgres;

--
-- TOC entry 458 (class 1255 OID 43157)
-- Name: queue_sms_on_status_change(); Type: FUNCTION; Schema: public; Owner: postgres
--

CREATE FUNCTION public.queue_sms_on_status_change() RETURNS trigger
    LANGUAGE plpgsql
    AS $$
DECLARE
  to_raw text;
  to_norm text;
  body text;
  s text := upper(NEW.status);
  fallback_phone text;
BEGIN
  IF s NOT IN ('APPROVED','REJECTED') THEN
    RETURN NEW;
  END IF;

  -- Choose a phone number (contact -> mother -> father -> applicants_main.phone_number by email)
  to_raw := COALESCE(NEW.contact_number, NEW.mother_number, NEW.father_number);
  IF to_raw IS NULL AND NEW.email IS NOT NULL THEN
    SELECT am.phone_number INTO fallback_phone
    FROM public.applicants_main am
    WHERE am.email = NEW.email
    LIMIT 1;
    to_raw := fallback_phone;
  END IF;

  to_norm := public.normalize_phone_ph(to_raw);

  -- Use custom message if provided; otherwise templated by status
  body := COALESCE(NULLIF(btrim(NEW.message), ''),
    CASE
      WHEN s = 'APPROVED' THEN
        format('Hi %s, good news! Your %s application has been APPROVED. Please check your email for next steps. - PRMSU Scholarships',
               COALESCE(NEW."Name",'Applicant'), COALESCE(NEW.scholarship_program,'scholarship'))
      ELSE
        format('Hi %s, thank you for applying to %s. After review, your application was not selected. You may reapply next term. - PRMSU Scholarships',
               COALESCE(NEW."Name",'Applicant'), COALESCE(NEW.scholarship_program,'the program'))
    END
  );

  IF to_norm IS NULL THEN
    INSERT INTO public.sms_outbox (applicant_id, email, to_number, message, status, error)
    VALUES (NEW.id, NEW.email, to_raw, body, 'skipped', 'missing or invalid phone');
  ELSE
    INSERT INTO public.sms_outbox (applicant_id, email, to_number, message, status)
    VALUES (NEW.id, NEW.email, to_norm, body, 'queued');
  END IF;

  RETURN NEW;
END;
$$;


ALTER FUNCTION public.queue_sms_on_status_change() OWNER TO postgres;

SET default_tablespace = '';

SET default_table_access_method = heap;

--
-- TOC entry 313 (class 1259 OID 17784)
-- Name: admins; Type: TABLE; Schema: public; Owner: postgres
--

CREATE TABLE public.admins (
    admin_id uuid DEFAULT gen_random_uuid() NOT NULL,
    full_name text NOT NULL,
    email text NOT NULL,
    phone_number text,
    role text NOT NULL,
    scholarship_assigned text,
    campus text,
    password text NOT NULL,
    created_at timestamp without time zone DEFAULT now(),
    CONSTRAINT admins_role_check CHECK ((role = ANY (ARRAY['super_admin'::text, 'main_admin'::text, 'program_admin'::text])))
);


ALTER TABLE public.admins OWNER TO postgres;

--
-- TOC entry 317 (class 1259 OID 22749)
-- Name: applicants_iskolar; Type: TABLE; Schema: public; Owner: postgres
--

CREATE TABLE public.applicants_iskolar (
    id bigint NOT NULL,
    created_at timestamp with time zone DEFAULT now() NOT NULL,
    "Name" text,
    scholarship_program text,
    birthdate date,
    campus text,
    address text,
    mother_name text,
    mother_number text,
    father_name text,
    father_number text,
    status text,
    email text,
    contact_number text,
    course text,
    year_level text,
    upload_requirements jsonb,
    department text,
    message text
);


ALTER TABLE public.applicants_iskolar OWNER TO postgres;

--
-- TOC entry 318 (class 1259 OID 22752)
-- Name: applicants_iskolar_id_seq; Type: SEQUENCE; Schema: public; Owner: postgres
--

ALTER TABLE public.applicants_iskolar ALTER COLUMN id ADD GENERATED BY DEFAULT AS IDENTITY (
    SEQUENCE NAME public.applicants_iskolar_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1
);


--
-- TOC entry 314 (class 1259 OID 17917)
-- Name: applicants_main; Type: TABLE; Schema: public; Owner: postgres
--

CREATE TABLE public.applicants_main (
    applicant_id uuid DEFAULT gen_random_uuid() NOT NULL,
    full_name text NOT NULL,
    student_number character varying NOT NULL,
    email text NOT NULL,
    age integer,
    birthdate date,
    campus text,
    college text,
    course text,
    password text NOT NULL,
    phone_number text,
    created_at timestamp without time zone DEFAULT now(),
    updated_at timestamp with time zone,
    CONSTRAINT applicants_campus_check CHECK ((campus = ANY (ARRAY['PRMSU Castillejos'::text, 'PRMSU San Marcelino'::text, 'PRMSU Iba'::text, 'PRMSU Masinloc'::text, 'PRMSU Candelaria'::text, 'PRMSU Sta. Cruz'::text])))
);


ALTER TABLE public.applicants_main OWNER TO postgres;

--
-- TOC entry 321 (class 1259 OID 40734)
-- Name: history_applicants; Type: TABLE; Schema: public; Owner: postgres
--

CREATE TABLE public.history_applicants (
    id bigint NOT NULL,
    decided_at timestamp with time zone DEFAULT now() NOT NULL,
    "Name" text,
    "Scholarship_Program" text,
    "Campus" text,
    "Address" text,
    "Status" text,
    decided_by text
);


ALTER TABLE public.history_applicants OWNER TO postgres;

--
-- TOC entry 322 (class 1259 OID 40737)
-- Name: history_applicants_id_seq; Type: SEQUENCE; Schema: public; Owner: postgres
--

ALTER TABLE public.history_applicants ALTER COLUMN id ADD GENERATED BY DEFAULT AS IDENTITY (
    SEQUENCE NAME public.history_applicants_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1
);


--
-- TOC entry 329 (class 1259 OID 43088)
-- Name: notifications; Type: TABLE; Schema: public; Owner: postgres
--

CREATE TABLE public.notifications (
    id integer NOT NULL,
    email text NOT NULL,
    message text NOT NULL,
    created_at timestamp without time zone DEFAULT now(),
    read boolean DEFAULT false
);


ALTER TABLE public.notifications OWNER TO postgres;

--
-- TOC entry 328 (class 1259 OID 43087)
-- Name: notifications_id_seq; Type: SEQUENCE; Schema: public; Owner: postgres
--

CREATE SEQUENCE public.notifications_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER SEQUENCE public.notifications_id_seq OWNER TO postgres;

--
-- TOC entry 3823 (class 0 OID 0)
-- Dependencies: 328
-- Name: notifications_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: postgres
--

ALTER SEQUENCE public.notifications_id_seq OWNED BY public.notifications.id;


--
-- TOC entry 316 (class 1259 OID 20330)
-- Name: scholarships; Type: TABLE; Schema: public; Owner: postgres
--

CREATE TABLE public.scholarships (
    id bigint NOT NULL,
    name text NOT NULL,
    grade text NOT NULL,
    requirements text[] NOT NULL,
    amount text NOT NULL,
    description text NOT NULL,
    created_at timestamp without time zone DEFAULT now()
);


ALTER TABLE public.scholarships OWNER TO postgres;

--
-- TOC entry 315 (class 1259 OID 20329)
-- Name: scholarships_id_seq; Type: SEQUENCE; Schema: public; Owner: postgres
--

ALTER TABLE public.scholarships ALTER COLUMN id ADD GENERATED BY DEFAULT AS IDENTITY (
    SEQUENCE NAME public.scholarships_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1
);


--
-- TOC entry 331 (class 1259 OID 43142)
-- Name: sms_outbox; Type: TABLE; Schema: public; Owner: postgres
--

CREATE TABLE public.sms_outbox (
    id bigint NOT NULL,
    applicant_id bigint NOT NULL,
    email text,
    to_number text,
    message text NOT NULL,
    status text DEFAULT 'queued'::text NOT NULL,
    provider_message_id text,
    error text,
    attempts integer DEFAULT 0 NOT NULL,
    created_at timestamp with time zone DEFAULT now() NOT NULL,
    sent_at timestamp with time zone,
    updated_at timestamp with time zone DEFAULT now() NOT NULL,
    CONSTRAINT sms_outbox_status_check CHECK ((status = ANY (ARRAY['queued'::text, 'sent'::text, 'failed'::text, 'skipped'::text])))
);


ALTER TABLE public.sms_outbox OWNER TO postgres;

--
-- TOC entry 330 (class 1259 OID 43141)
-- Name: sms_outbox_id_seq; Type: SEQUENCE; Schema: public; Owner: postgres
--

CREATE SEQUENCE public.sms_outbox_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER SEQUENCE public.sms_outbox_id_seq OWNER TO postgres;

--
-- TOC entry 3828 (class 0 OID 0)
-- Dependencies: 330
-- Name: sms_outbox_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: postgres
--

ALTER SEQUENCE public.sms_outbox_id_seq OWNED BY public.sms_outbox.id;


--
-- TOC entry 3601 (class 2604 OID 43091)
-- Name: notifications id; Type: DEFAULT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.notifications ALTER COLUMN id SET DEFAULT nextval('public.notifications_id_seq'::regclass);


--
-- TOC entry 3604 (class 2604 OID 43145)
-- Name: sms_outbox id; Type: DEFAULT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.sms_outbox ALTER COLUMN id SET DEFAULT nextval('public.sms_outbox_id_seq'::regclass);


--
-- TOC entry 3794 (class 0 OID 17784)
-- Dependencies: 313
-- Data for Name: admins; Type: TABLE DATA; Schema: public; Owner: postgres
--

COPY public.admins (admin_id, full_name, email, phone_number, role, scholarship_assigned, campus, password, created_at) FROM stdin;
80d2b836-5e9d-46c7-8e59-9460c0ca8699	Joshua Tenorio	tenoriojoshua0112@gmail.com	09125678943	main_admin	\N	PRMSU Iba	joshua12345	2025-10-05 15:09:46.018596
175e03dc-ea6f-415d-9da7-9479646aba56	Rhonielyn Tolentino	barrera.lyn29@gmail.com	09107050919	super_admin	\N	\N	rhonielyn12345	2025-10-05 14:55:36.082349
14a2917d-b22e-40ac-a667-a90f9379fdc7	Mekaila	mekailaadamos@gmail.com	09615309822	main_admin	\N	San Marcelino	mekai123	2025-10-07 02:28:46.377752
bbde5a4d-2306-4429-b9ef-4bc69b3ff487	Dio Tadena	diod25105@gmail.com	09158349447	program_admin	\N	Iba	dio123	2025-10-07 13:46:54.833692
77cc5b3a-2132-4d6f-a557-00bb9fff8e69	Aryie Joshua	aryieljoshua1905@gmail.com	09615309822	program_admin	TAP	Masinloc	aryiel123	2025-10-08 04:14:59.76059
\.


--
-- TOC entry 3798 (class 0 OID 22749)
-- Dependencies: 317
-- Data for Name: applicants_iskolar; Type: TABLE DATA; Schema: public; Owner: postgres
--

COPY public.applicants_iskolar (id, created_at, "Name", scholarship_program, birthdate, campus, address, mother_name, mother_number, father_name, father_number, status, email, contact_number, course, year_level, upload_requirements, department, message) FROM stdin;
16	2025-11-02 12:06:05.038173+00	Joshua Tenorio	Edukalinga	2005-12-12	IBA 	Purok 6 Obispo Street	Evelyn	09999999999	Alberto	09888888888	Approved	aureliotadena@gmail.com	\N	\N	\N	"{\\"grades\\":null,\\"indigency\\":null,\\"certificate_of_grades\\":\\"https://qdrnqkoozsloeqzxpgha.supabase.co/storage/v1/object/public/applicants_iskolar/requirements/fb326486-abb5-4cd9-9d15-26e2bb0f0e88/1762085161241_Screenshot%202025-08-14%20151806.png\\",\\"certificate_of_registration\\":\\"https://qdrnqkoozsloeqzxpgha.supabase.co/storage/v1/object/public/applicants_iskolar/requirements/fb326486-abb5-4cd9-9d15-26e2bb0f0e88/1762085162975_Screenshot%202025-10-20%20235910.png\\"}"	\N	\N
19	2025-11-03 15:04:51.908485+00	Joshua Tenorio	Tulong-Agri Program (TAP)	2000-02-02	Candelaria	Brgy San Pascual San Narciso Zambales	Evelyn	09999999999	Alberto	09888888888	Approved	tenoriojed16@gmail.com	\N	\N	\N	"{\\"grades\\":null,\\"indigency\\":null,\\"certified_true_copy_of_certificate_of_registration\\":\\"https://qdrnqkoozsloeqzxpgha.supabase.co/storage/v1/object/public/applicants_iskolar/requirements/ec116b59-e3d4-45a9-8aa7-ed947091672e/1762182289268_Screenshot%202025-11-02%20153247.png\\",\\"_police_clearance\\":\\"https://qdrnqkoozsloeqzxpgha.supabase.co/storage/v1/object/public/applicants_iskolar/requirements/ec116b59-e3d4-45a9-8aa7-ed947091672e/1762182289759_Screenshot%20(1).png\\",\\"_certificate_of_indigency\\":\\"https://qdrnqkoozsloeqzxpgha.supabase.co/storage/v1/object/public/applicants_iskolar/requirements/ec116b59-e3d4-45a9-8aa7-ed947091672e/1762182290291_Screenshot%20(9).png\\"}"	\N	
15	2025-11-02 11:55:40.428235+00	Joshua Tenorio	San Miguel Global Power (SMGP) Foundation's MPCL (Masinloc Power Corporation Limited)	2010-10-11	Sta Cruz	Purok 6 Obispo Street	Evelyn	09999999999	Alberto	09888888888	Approved	aureliotadena@gmail.com	\N	\N	\N	"{\\"grades\\":null,\\"indigency\\":null,\\"certified_true_copy_of_certificate_of_registration\\":\\"https://qdrnqkoozsloeqzxpgha.supabase.co/storage/v1/object/public/applicants_iskolar/requirements/fb326486-abb5-4cd9-9d15-26e2bb0f0e88/1762084521464_Screenshot%202025-10-21%20140031.png\\",\\"_certificate_of_indigency\\":\\"https://qdrnqkoozsloeqzxpgha.supabase.co/storage/v1/object/public/applicants_iskolar/requirements/fb326486-abb5-4cd9-9d15-26e2bb0f0e88/1762084523046_Screenshot%202025-08-28%20175539.png\\"}"	\N	\N
18	2025-11-02 12:11:08.524036+00	Aurelio Tadena	Department of Science and Technology – Science Education Institute or DOST-SEI	2008-08-08	Botolan	Purok 6 Obispo Street	Evelyn	09999999999	Alberto	09888888888	Approved	aureliotadena@gmail.com	\N	\N	\N	"{\\"grades\\":null,\\"indigency\\":null,\\"certified_true_copy_of_certificate_of_registration\\":\\"https://qdrnqkoozsloeqzxpgha.supabase.co/storage/v1/object/public/applicants_iskolar/requirements/fb326486-abb5-4cd9-9d15-26e2bb0f0e88/1762085461137_new-lto-certificate-of-registration-604addbf02645.jpg\\",\\"_school_id\\":\\"https://qdrnqkoozsloeqzxpgha.supabase.co/storage/v1/object/public/applicants_iskolar/requirements/fb326486-abb5-4cd9-9d15-26e2bb0f0e88/1762085464056_564667216_1912548496326912_1876696592483635507_n.jpg\\",\\"_certificate_of_indigency\\":\\"https://qdrnqkoozsloeqzxpgha.supabase.co/storage/v1/object/public/applicants_iskolar/requirements/fb326486-abb5-4cd9-9d15-26e2bb0f0e88/1762085465800_How-to-Make-a-Report-Card-in-Excel-3.png\\"}"	\N	\N
14	2025-10-31 02:47:03.386553+00	Rhonielyn Tolentino	DA ACEF-GIAHEP (Agricultural Competitiveness Enhancement Fund – Grants-in-Aid for Higher Education Program)	2000-01-18	IBA 	Purok 6 Obispo Street	Evelyn	09999999999	Alberto	09888888888	Processing	aureliotadena@gmail.com	+639274538432	\N	\N	"{\\"grades\\":null,\\"indigency\\":null,\\"certified_true_copy_of_certificate_of_registration\\":\\"https://qdrnqkoozsloeqzxpgha.supabase.co/storage/v1/object/public/applicants_iskolar/requirements/fb326486-abb5-4cd9-9d15-26e2bb0f0e88/1761878753194_Screenshot%20(7).png\\",\\"_certificate_of_indigency\\":\\"https://qdrnqkoozsloeqzxpgha.supabase.co/storage/v1/object/public/applicants_iskolar/requirements/fb326486-abb5-4cd9-9d15-26e2bb0f0e88/1761878790354_Screenshot%20(9).png\\"}"	\N	Hi Rhonielyn Tolentino, your DA ACEF-GIAHEP (Agricultural Competitiveness Enhancement Fund – Grants-in-Aid for Higher Education Program) application is now marked as PROCESSING. We will notify you once a decision is made. - PRMSU Scholarships
20	2025-11-04 04:17:59.248986+00	Rhonielyn Tolentino	DA ACEF-GIAHEP (Agricultural Competitiveness Enhancement Fund – Grants-in-Aid for Higher Education Program)	2000-11-11	IBA 	Purok 6 Obispo Street	Evelyn	09999999999	Alberto	09888888888	Approved	t.rhonie29@gmail.com	\N	\N	\N	"{\\"grades\\":null,\\"indigency\\":null,\\"certified_true_copy_of_certificate_of_registration\\":\\"https://qdrnqkoozsloeqzxpgha.supabase.co/storage/v1/object/public/applicants_iskolar/requirements/ec116b59-e3d4-45a9-8aa7-ed947091672e/1762229869564_Acer_Wallpaper_02_3840x2400.jpg\\",\\"_certificate_of_indigency\\":\\"https://qdrnqkoozsloeqzxpgha.supabase.co/storage/v1/object/public/applicants_iskolar/requirements/ec116b59-e3d4-45a9-8aa7-ed947091672e/1762229873477_Acer_Wallpaper_03_3840x2400.jpg\\"}"	\N	\N
13	2025-10-28 15:53:56.68786+00	LovelyJoyce	DA ACEF-GIAHEP (Agricultural Competitiveness Enhancement Fund – Grants-in-Aid for Higher Education Program)	2005-05-18	San Marcelino	Purok 6 Obispo Street	Evelyn	09999999999	Alberto	09888888888	Approved	aureliotadena@gmail.com	09155186827	\N	\N	"{\\"grades\\":null,\\"indigency\\":null,\\"certified_true_copy_of_certificate_of_registration\\":\\"https://qdrnqkoozsloeqzxpgha.supabase.co/storage/v1/object/public/applicants_iskolar/requirements/fb326486-abb5-4cd9-9d15-26e2bb0f0e88/1761666830965_Screenshot%20(1).png\\",\\"_certificate_of_indigency\\":\\"https://qdrnqkoozsloeqzxpgha.supabase.co/storage/v1/object/public/applicants_iskolar/requirements/fb326486-abb5-4cd9-9d15-26e2bb0f0e88/1761666832656_Screenshot%20(1).png\\"}"	\N	\N
17	2025-11-02 12:10:06.400609+00	Rhonielyn Tolentino	Tertiary Education Subsidy (TES)	1999-11-11	Sta Cruz	Purok 6 Obispo Street	Evelyn	09999999999	Alberto	09888888888	Approved	aureliotadena@gmail.com	\N	\N	\N	"{\\"grades\\":null,\\"indigency\\":null,\\"certificate_of_grades_\\":\\"https://qdrnqkoozsloeqzxpgha.supabase.co/storage/v1/object/public/applicants_iskolar/requirements/fb326486-abb5-4cd9-9d15-26e2bb0f0e88/1762085351949_Screenshot%202025-10-28%20215604.png\\",\\"_certified_true_copy_of_certificate_of_registration\\":\\"https://qdrnqkoozsloeqzxpgha.supabase.co/storage/v1/object/public/applicants_iskolar/requirements/fb326486-abb5-4cd9-9d15-26e2bb0f0e88/1762085354244_Screenshot%20(1).png\\",\\"_certificate_of_indigency\\":\\"https://qdrnqkoozsloeqzxpgha.supabase.co/storage/v1/object/public/applicants_iskolar/requirements/fb326486-abb5-4cd9-9d15-26e2bb0f0e88/1762085371922_Screenshot%202025-10-27%20213624.png\\"}"	\N	\N
21	2025-11-04 04:23:31.788464+00	Joshua Tenorio	Department of Science and Technology – Science Education Institute or DOST-SEI	2000-12-12	Sta Cruz	Purok 6 Obispo Street	Evelyn	09999999999	Alberto	09888888888	Approved	tenoriojed16@gmail.com	\N	\N	\N	"{\\"grades\\":null,\\"indigency\\":null,\\"certified_true_copy_of_certificate_of_registration\\":\\"https://qdrnqkoozsloeqzxpgha.supabase.co/storage/v1/object/public/applicants_iskolar/requirements/ec116b59-e3d4-45a9-8aa7-ed947091672e/1762230200208_Acer_Wallpaper_03_3840x2400.jpg\\",\\"_school_id\\":\\"https://qdrnqkoozsloeqzxpgha.supabase.co/storage/v1/object/public/applicants_iskolar/requirements/ec116b59-e3d4-45a9-8aa7-ed947091672e/1762230205327_Acer_Wallpaper_02_3840x2400.jpg\\",\\"_certificate_of_indigency\\":\\"https://qdrnqkoozsloeqzxpgha.supabase.co/storage/v1/object/public/applicants_iskolar/requirements/ec116b59-e3d4-45a9-8aa7-ed947091672e/1762230208502_Acer_Wallpaper_01_3840x2400.jpg\\"}"	\N	
22	2025-11-04 04:26:30.360863+00	Angelica Aquino	Tulong-Agri Program (TAP)	2002-02-02	Botolan	Purok 6 Obispo Street	Evelyn	09999999999	Alberto	09888888888	Rejected	aureliotadena@gmail.com	\N	\N	\N	"{\\"grades\\":null,\\"indigency\\":null,\\"certified_true_copy_of_certificate_of_registration\\":\\"https://qdrnqkoozsloeqzxpgha.supabase.co/storage/v1/object/public/applicants_iskolar/requirements/ec116b59-e3d4-45a9-8aa7-ed947091672e/1762230377424_Acer_Wallpaper_01_3840x2400.jpg\\",\\"_police_clearance\\":\\"https://qdrnqkoozsloeqzxpgha.supabase.co/storage/v1/object/public/applicants_iskolar/requirements/ec116b59-e3d4-45a9-8aa7-ed947091672e/1762230380606_Acer_Wallpaper_02_3840x2400.jpg\\",\\"_certificate_of_indigency\\":\\"https://qdrnqkoozsloeqzxpgha.supabase.co/storage/v1/object/public/applicants_iskolar/requirements/ec116b59-e3d4-45a9-8aa7-ed947091672e/1762230383600_Acer_Wallpaper_03_3840x2400.jpg\\"}"	\N	\N
23	2025-11-04 04:28:03.197414+00	Joshua Tenorio	Edukalinga	2000-02-22	Masinloc	Purok 6 Obispo Street	Evelyn	09999999999	Alberto	09888888888	Rejected	aureliotadena@gmail.com	\N	\N	\N	"{\\"grades\\":null,\\"indigency\\":null,\\"certificate_of_grades\\":\\"https://qdrnqkoozsloeqzxpgha.supabase.co/storage/v1/object/public/applicants_iskolar/requirements/ec116b59-e3d4-45a9-8aa7-ed947091672e/1762230474553_Acer_Wallpaper_01_3840x2400.jpg\\",\\"certificate_of_registration\\":\\"https://qdrnqkoozsloeqzxpgha.supabase.co/storage/v1/object/public/applicants_iskolar/requirements/ec116b59-e3d4-45a9-8aa7-ed947091672e/1762230478183_Acer_Wallpaper_02_3840x2400.jpg\\"}"	\N	\N
26	2025-11-04 12:16:20.85037+00	Rhonielyn Tolentino	ACEF-GIAHEP (Agricultural Competitiveness Enhancement Fund - Grants-in-Aid for Higher Education Program)	2001-11-11	San Marcelino	Purok 6 Obispo Street	Evelyn	09999999999	Alberto	09888888888	Pending	t.rhonie29@gmail.com	09274538432	\N	\N	"{\\"grades\\":null,\\"indigency\\":null,\\"certified_true_copy_of_certificate_of_registration\\":\\"https://qdrnqkoozsloeqzxpgha.supabase.co/storage/v1/object/public/applicants_iskolar/requirements/ec116b59-e3d4-45a9-8aa7-ed947091672e/1762258556457_Screenshot%202025-10-31%20104237.png\\",\\"_certificate_of_indigency\\":\\"https://qdrnqkoozsloeqzxpgha.supabase.co/storage/v1/object/public/applicants_iskolar/requirements/ec116b59-e3d4-45a9-8aa7-ed947091672e/1762258561149_Screenshot%20(7).png\\"}"	\N	\N
29	2025-11-04 12:52:01.992638+00	Aurelio Tadena	Tulong-Agri Program (TAP)	20009-09-09	Botolan	Purok 6 Obispo Street	Evelyn	09999999999	Alberto	09888888888	Rejected	aureliotadena@gmail.com	\N	\N	\N	"{\\"grades\\":null,\\"indigency\\":null,\\"certified_true_copy_of_certificate_of_registration\\":\\"https://qdrnqkoozsloeqzxpgha.supabase.co/storage/v1/object/public/applicants_iskolar/requirements/ec116b59-e3d4-45a9-8aa7-ed947091672e/1762260713423_Screenshot%20(1).png\\",\\"_police_clearance\\":\\"https://qdrnqkoozsloeqzxpgha.supabase.co/storage/v1/object/public/applicants_iskolar/requirements/ec116b59-e3d4-45a9-8aa7-ed947091672e/1762260717952_Screenshot%202025-11-04%20204321.png\\",\\"_certificate_of_indigency\\":\\"https://qdrnqkoozsloeqzxpgha.supabase.co/storage/v1/object/public/applicants_iskolar/requirements/ec116b59-e3d4-45a9-8aa7-ed947091672e/1762260719599_Screenshot%202025-11-03%20234158.png\\"}"	\N	\N
28	2025-11-04 12:45:32.303664+00	Joshua Tenorio	Department of Science and Technology – Science Education Institute or DOST-SEI	2001-01-01	IBA 	Brgy La Paz Purok 5 San Narciso Zambales	Evelyn	09999999999	Alberto	09888888888	Processing	tenoriojed16@gmail.com	09274538432	\N	\N	"{\\"grades\\":null,\\"indigency\\":null,\\"certified_true_copy_of_certificate_of_registration\\":\\"https://qdrnqkoozsloeqzxpgha.supabase.co/storage/v1/object/public/applicants_iskolar/requirements/ec116b59-e3d4-45a9-8aa7-ed947091672e/1762260325763_Screenshot%202025-11-04%20204321.png\\",\\"_school_id\\":\\"https://qdrnqkoozsloeqzxpgha.supabase.co/storage/v1/object/public/applicants_iskolar/requirements/ec116b59-e3d4-45a9-8aa7-ed947091672e/1762260327360_Screenshot%20(1).png\\",\\"_certificate_of_indigency\\":\\"https://qdrnqkoozsloeqzxpgha.supabase.co/storage/v1/object/public/applicants_iskolar/requirements/ec116b59-e3d4-45a9-8aa7-ed947091672e/1762260329546_Screenshot%202025-11-04%20204126.png\\"}"	\N	Hi Joshua Tenorio, your Department of Science and Technology – Science Education Institute or DOST-SEI application is now marked as PROCESSING. We will notify you once a decision is made. - PRMSU Scholarships
24	2025-11-04 04:30:28.796187+00	Joshua Tenorio	TULONG DUNONG PROGRAM	2000-02-02	Masinloc	Purok 6 Obispo Street	Evelyn	09999999999	Alberto	09888888888	Rejected	tenoriojed16@gmail.com	\N	\N	\N	"{\\"grades\\":null,\\"indigency\\":null,\\"certified_true_copy_of_certificate_of_registration\\":\\"https://qdrnqkoozsloeqzxpgha.supabase.co/storage/v1/object/public/applicants_iskolar/requirements/ec116b59-e3d4-45a9-8aa7-ed947091672e/1762230621839_Acer_Wallpaper_02_3840x2400.jpg\\",\\"_certificate_of_indigency\\":\\"https://qdrnqkoozsloeqzxpgha.supabase.co/storage/v1/object/public/applicants_iskolar/requirements/ec116b59-e3d4-45a9-8aa7-ed947091672e/1762230625171_Acer_Wallpaper_01_3840x2400.jpg\\"}"	\N	
25	2025-11-04 12:09:36.372743+00	Joshua Tenorio	Edukalinga	2005-05-05	Candelaria	Purok 6 Obispo Street	Evelyn	09999999999	Alberto	09888888888	Approved	tenoriojed16@gmail.com	+639615309822	\N	\N	"{\\"grades\\":null,\\"indigency\\":null,\\"certificate_of_grades\\":null,\\"certificate_of_registration\\":\\"https://qdrnqkoozsloeqzxpgha.supabase.co/storage/v1/object/public/applicants_iskolar/requirements/ec116b59-e3d4-45a9-8aa7-ed947091672e/1762257935777_Acer_Wallpaper_01_3840x2400.jpg\\"}"	\N	Hi Joshua Tenorio, good news! Your Edukalinga application has been APPROVED. Please check your email for next steps. - PRMSU Scholarships
27	2025-11-04 12:39:09.069812+00	Joshua Tenorio	National Grid Corporation of the Philippines	2002-02-02	Sta Cruz	Brgy San Pascual San Narciso Zambales	Evelyn	09999999999	Alberto	09888888888	Approved	tenoriojed16@gmail.com	+639615309822	\N	\N	"{\\"grades\\":null,\\"indigency\\":null,\\"certified_true_copy_of_certificate_of_registration\\":\\"https://qdrnqkoozsloeqzxpgha.supabase.co/storage/v1/object/public/applicants_iskolar/requirements/ec116b59-e3d4-45a9-8aa7-ed947091672e/1762259944142_Screenshot%20(1).png\\",\\"_certificate_of_residency\\":\\"https://qdrnqkoozsloeqzxpgha.supabase.co/storage/v1/object/public/applicants_iskolar/requirements/ec116b59-e3d4-45a9-8aa7-ed947091672e/1762259946888_Screenshot%202025-11-03%20234158.png\\"}"	\N	Hi Joshua Tenorio, your National Grid Corporation of the Philippines application is now marked as PROCESSING. We will notify you once a decision is made. - PRMSU Scholarships
\.


--
-- TOC entry 3795 (class 0 OID 17917)
-- Dependencies: 314
-- Data for Name: applicants_main; Type: TABLE DATA; Schema: public; Owner: postgres
--

COPY public.applicants_main (applicant_id, full_name, student_number, email, age, birthdate, campus, college, course, password, phone_number, created_at, updated_at) FROM stdin;
72d7da1c-09d3-41f3-b9d2-a51c1bbae416	Dave Anthony Ulanday	23-1-1-2091	daveculanday0419@gmail.com	20	2005-04-19	PRMSU Iba	College of Communication and Information Technology (CCIT)	Bachelor of Science in Computer Science	dave12345	09345678291	2025-10-05 17:22:17.966	\N
340fec48-6541-486f-b372-e6f40963a5e6	Aurelio Tadena	23-1-1-0608	aureliotadena@gmail.com	22	2005-05-18	PRMSU Iba	College of Communication and Information Technology (CCIT)	Bachelor of Science in Computer Science	dio12345	09219329123	2025-10-06 03:41:27.239	2025-10-06 18:23:12.74+00
3a151fd5-fbfe-4f0f-83ff-b6a438bf4ab8	Rhonie Tolentino	23-1-1-0011	t.rhonie29@gmail.com	24	2005-06-29	PRMSU Iba	College of Communication and Information Technology (CCIT)	Bachelor of Science in Computer Science	mhei12345	09107050919	2025-10-05 17:39:44.404	2025-10-06 18:30:17.609+00
8721aa45-52df-4460-8d0d-5e8e8d7a88f4	Mario love chuchay		marionavarro.1726@gmail.com	22	2003-08-26	PRMSU Iba	College of Industrial Technology (CIT)	Bachelor of Science in Industrial Technology	12345678910	09165882810	2025-10-08 16:10:03.899	\N
03d1f105-3ec4-47fb-91c6-4b297fddca7f	Josh Tenorio	23-1-1-2081	tenoriojed16@gmail.com	20	2005-04-19	PRMSU Castillejos	College of Business, Accountancy and Public Administration (CBAPA)	Bachelor of Science in Business Administration Major in Human Resource Management	joshua12345	09123456789	2025-10-05 17:25:53.997	2025-11-03 15:06:23.679+00
\.


--
-- TOC entry 3800 (class 0 OID 40734)
-- Dependencies: 321
-- Data for Name: history_applicants; Type: TABLE DATA; Schema: public; Owner: postgres
--

COPY public.history_applicants (id, decided_at, "Name", "Scholarship_Program", "Campus", "Address", "Status", decided_by) FROM stdin;
5	2025-11-02 08:33:59.713+00	Rhonielyn Tolentino	DA ACEF-GIAHEP (Agricultural Competitiveness Enhancement Fund – Grants-in-Aid for Higher Education Program)	IBA 	Purok 6 Obispo Street	Approved	\N
6	2025-11-02 08:57:35.01+00	Aurelio Tadena	DA ACEF-GIAHEP (Agricultural Competitiveness Enhancement Fund – Grants-in-Aid for Higher Education Program)	San Marcelino	Purok 6 Obispo Street	Rejected	\N
7	2025-11-02 09:06:01.251+00	Joshua Tenorio	National Grid Corporation of the Philippines	San Marcelino	Brgy San Pascual San Narciso Zambales	Rejected	\N
8	2025-11-02 09:07:45.75+00	Rhonielyn Tolentino	DA ACEF-GIAHEP (Agricultural Competitiveness Enhancement Fund – Grants-in-Aid for Higher Education Program)	IBA 	Purok 6 Obispo Street	Rejected	\N
9	2025-11-02 09:11:52.683+00	Joshua Tenorio	DA ACEF-GIAHEP (Agricultural Competitiveness Enhancement Fund – Grants-in-Aid for Higher Education Program)	Botolan	Brgy San Pascual San Narciso Zambales	Rejected	\N
10	2025-11-02 09:14:19.084+00	Rhonielyn Tolentino	DA ACEF-GIAHEP (Agricultural Competitiveness Enhancement Fund – Grants-in-Aid for Higher Education Program)	IBA 	Purok 6 Obispo Street	Approved	aureliotadena@gmail.com
11	2025-11-02 09:15:29.067+00	Aurelio Tadena	DA ACEF-GIAHEP (Agricultural Competitiveness Enhancement Fund – Grants-in-Aid for Higher Education Program)	San Marcelino	Purok 6 Obispo Street	Approved	aureliotadena@gmail.com
12	2025-11-02 09:17:28.438+00	Joshua Tenorio	National Grid Corporation of the Philippines	San Marcelino	Brgy San Pascual San Narciso Zambales	Approved	aureliotadena@gmail.com
13	2025-11-02 09:18:18.739+00	Rhonielyn Tolentino	DA ACEF-GIAHEP (Agricultural Competitiveness Enhancement Fund – Grants-in-Aid for Higher Education Program)	IBA 	Purok 6 Obispo Street	Rejected	aureliotadena@gmail.com
14	2025-11-02 12:06:29.507+00	Joshua Tenorio	Edukalinga	IBA 	Purok 6 Obispo Street	Approved	Unknown Admin
15	2025-11-02 12:11:21.211+00	Aurelio Tadena	Department of Science and Technology – Science Education Institute or DOST-SEI	Botolan	Purok 6 Obispo Street	Processing	Unknown Admin
16	2025-11-04 04:12:54.192+00	Joshua Tenorio	Tulong-Agri Program (TAP)	Candelaria	Brgy San Pascual San Narciso Zambales	Approved	Unknown Admin
17	2025-11-04 04:18:15.092+00	Rhonielyn Tolentino	Tertiary Education Subsidy (TES)	Sta Cruz	Purok 6 Obispo Street	Approved	Unknown Admin
18	2025-11-04 04:18:46.989+00	Rhonielyn Tolentino	DA ACEF-GIAHEP (Agricultural Competitiveness Enhancement Fund – Grants-in-Aid for Higher Education Program)	IBA 	Purok 6 Obispo Street	Approved	Unknown Admin
19	2025-11-04 04:23:55.74+00	Joshua Tenorio	Department of Science and Technology – Science Education Institute or DOST-SEI	Sta Cruz	Purok 6 Obispo Street	Approved	Josh Tenorio
20	2025-11-04 04:28:01.575+00	Angelica Aquino	Tulong-Agri Program (TAP)	Botolan	Purok 6 Obispo Street	Rejected	Josh Tenorio
21	2025-11-04 04:30:53.74+00	Joshua Tenorio	Edukalinga	Masinloc	Purok 6 Obispo Street	Rejected	Josh Tenorio
22	2025-11-04 04:31:23.186+00	Joshua Tenorio	TULONG DUNONG PROGRAM	Masinloc	Purok 6 Obispo Street	Rejected	Josh Tenorio
23	2025-11-04 13:01:23.273+00	Aurelio Tadena	Tulong-Agri Program (TAP)	Botolan	Purok 6 Obispo Street	Rejected	Josh Tenorio
\.


--
-- TOC entry 3803 (class 0 OID 43088)
-- Dependencies: 329
-- Data for Name: notifications; Type: TABLE DATA; Schema: public; Owner: postgres
--

COPY public.notifications (id, email, message, created_at, read) FROM stdin;
\.


--
-- TOC entry 3797 (class 0 OID 20330)
-- Dependencies: 316
-- Data for Name: scholarships; Type: TABLE DATA; Schema: public; Owner: postgres
--

COPY public.scholarships (id, name, grade, requirements, amount, description, created_at) FROM stdin;
9	National Grid Corporation of the Philippines	90	{"CERTIFIED TRUE COPY OF CERTIFICATE OF REGISTRATION"," CERTIFICATE OF RESIDENCY"}	15,000 per semester	The NGCP Scholarship Program is a corporate social initiative of the National Grid Corporation of the Philippines that offers educational assistance to deserving students from communities hosting NGCP facilities.\nIt aims to empower financially challenged but capable students, particularly those pursuing engineering and other technical courses, by providing tuition support and allowances to help them finish their studies and contribute to the country’s development in the energy sector.	2025-10-07 17:22:37.186692
7	TULONG DUNONG PROGRAM	90	{"CERTIFIED TRUE COPY OF CERTIFICATE OF REGISTRATION"," CERTIFICATE OF INDIGENCY"}	7,500 to 15,000 per semester	The Tulong Dunong Program (TDP) is a financial aid initiative by CHED that offers monetary assistance to eligible and deserving Filipino students studying in public or private higher education institutions (HEIs).\nIts main goal is to help reduce the financial challenges of paying for tuition and other school expenses, giving students from low-income families the opportunity to pursue and continue their college education.	2025-10-07 17:18:48.248481
16	DA ACEF-GIAHEP (Agricultural Competitiveness Enhancement Fund – Grants-in-Aid for Higher Education Program)	90	{"CERTIFIED TRUE COPY OF CERTIFICATE OF REGISTRATION"," CERTIFICATE OF INDIGENCY"}	10,000 per semester	The ACEF-GIAHEP is a government scholarship initiative under the Department of Agriculture (DA) and the Commission on Higher Education (CHED), aimed at supporting Filipino students pursuing higher education in agriculture and related fields. The program seeks to develop a skilled workforce that will contribute to the competitiveness and sustainability of the Philippine agriculture sector.	2025-10-07 17:49:42.610891
11	Tertiary Education Subsidy (TES)	90	{"CERTIFICATE OF GRADES "," CERTIFIED TRUE COPY OF CERTIFICATE OF REGISTRATION"," CERTIFICATE OF INDIGENCY"}	40,000 per academic year	The Tertiary Education Subsidy (TES) is a government financial assistance program under the Universal Access to Quality Tertiary Education Act (RA 10931).\nIt aims to support students from low-income families who are enrolled in state universities and colleges (SUCs), local universities and colleges (LUCs), and CHED-recognized private higher education institutions (HEIs).	2025-10-07 17:29:32.585076
18	Edukalinga	90	{"Certificate of Grades","Certificate of Registration"}	3000 	ddssssssssssssssss\nfdfdfdf\n\ndfdfdfdfd\nfdfff	2025-10-27 02:01:12.262853
8	Department of Science and Technology – Science Education Institute or DOST-SEI	90	{"CERTIFIED TRUE COPY OF CERTIFICATE OF REGISTRATION"," SCHOOL ID"," CERTIFICATE OF INDIGENCY"}	40,000 per academic year	The DOST-SEI Scholarship Program is a government-funded initiative designed to nurture the next generation of scientists, engineers, and researchers in the Philippines.\nIt offers comprehensive financial assistance to qualified and deserving students who wish to pursue STEM-related degree programs in accredited higher education institutions (HEIs) across the country.	2025-10-07 17:21:12.224131
10	Tulong-Agri Program (TAP)	90	{"CERTIFIED TRUE COPY OF CERTIFICATE OF REGISTRATION"," POLICE CLEARANCE"," CERTIFICATE OF INDIGENCY"}	47,000 per academic year	The CHED Tulong-Agri Program (TAP) is a financial assistance initiative by the Commission on Higher Education (CHED) that supports students pursuing agriculture, fisheries, forestry, food technology, and other related courses in accredited colleges and universities.\nIts main goal is to encourage more students to take agriculture-related programs by providing tuition coverage, monthly stipends, and book allowances to qualified beneficiaries.\n	2025-10-07 17:26:04.209368
12	ACEF-GIAHEP (Agricultural Competitiveness Enhancement Fund - Grants-in-Aid for Higher Education Program)	90	{"CERTIFIED TRUE COPY OF CERTIFICATE OF REGISTRATION"," CERTIFICATE OF INDIGENCY"}	40,000 per academic year	The ACEF-GIAHEP is a scholarship/grant-in-aid program under the Department of Agriculture (DA) and the Commission on Higher Education (CHED) in the Philippines. Its goal is to support the development of the agriculture and fisheries sector by helping more students finish higher education in related fields (agriculture, forestry, fisheries, veterinary medicine, and other agricultural education programs). It especially targets deserving and qualified students from low-income families to build scientific, technical, and entrepreneurial skills for these sectors.	2025-10-07 17:31:48.521137
13	San Miguel Global Power Foundation's ENGINE (SMCGP ENGINE)	90	{"CERTIFIED TRUE COPY OF CERTIFICATE OF REGISTRATION"," PHILIPPINES STATISTIC AUTHORITY CERTIFICATE OF BIRTH"}	15,000 per semester	The ENGINE Scholarship is an initiative by the San Miguel Global Power Foundation aimed at supporting deserving students pursuing engineering degrees, particularly those from local communities near San Miguel Global Power's operations. The program focuses on developing a new generation of engineers who are innovative and equipped to contribute to the energy sector.	2025-10-07 17:39:51.333688
15	San Miguel Global Power (SMGP) Foundation's MPCL (Masinloc Power Corporation Limited)	90	{"CERTIFIED TRUE COPY OF CERTIFICATE OF REGISTRATION"," CERTIFICATE OF INDIGENCY"}	15,000 per semester	The MPCL Scholarship provides financial assistance to students pursuing higher education, particularly in fields related to energy, engineering, and other disciplines relevant to the operations of the Masinloc Power Plant. The program aims to develop a skilled workforce capable of contributing to the energy sector and the local community.	2025-10-07 17:44:21.274689
\.


--
-- TOC entry 3805 (class 0 OID 43142)
-- Dependencies: 331
-- Data for Name: sms_outbox; Type: TABLE DATA; Schema: public; Owner: postgres
--

COPY public.sms_outbox (id, applicant_id, email, to_number, message, status, provider_message_id, error, attempts, created_at, sent_at, updated_at) FROM stdin;
4	25	tenoriojed16@gmail.com	+639615309822	Hi Joshua Tenorio, your Edukalinga application is now marked as PROCESSING. We will notify you once a decision is made. - PRMSU Scholarships	sent	\N	\N	1	2025-11-05 05:37:43.327923+00	2025-11-05 05:37:51.154346+00	2025-11-05 05:37:51.154346+00
5	14	aureliotadena@gmail.com	+639274538432	Hi Rhonielyn Tolentino, your DA ACEF-GIAHEP (Agricultural Competitiveness Enhancement Fund – Grants-in-Aid for Higher Education Program) application is now marked as PROCESSING. We will notify you once a decision is made. - PRMSU Scholarships	sent	\N	\N	1	2025-11-05 05:41:03.591264+00	2025-11-05 05:41:17.062171+00	2025-11-05 05:41:17.062171+00
6	25	tenoriojed16@gmail.com	+639615309822	Hi Joshua Tenorio, good news! Your Edukalinga application has been APPROVED. Please check your email for next steps. - PRMSU Scholarships	failed	\N	Error: The number +63961530XXXX is unverified. Trial accounts cannot send messages to unverified numbers; verify +63961530XXXX at twilio.com/user/account/phone-numbers/verified, or purchase a Twilio number to send messages to unverified numbers	1	2025-11-05 05:58:48.702735+00	\N	2025-11-05 05:59:05.887013+00
\.


--
-- TOC entry 3830 (class 0 OID 0)
-- Dependencies: 318
-- Name: applicants_iskolar_id_seq; Type: SEQUENCE SET; Schema: public; Owner: postgres
--

SELECT pg_catalog.setval('public.applicants_iskolar_id_seq', 29, true);


--
-- TOC entry 3831 (class 0 OID 0)
-- Dependencies: 322
-- Name: history_applicants_id_seq; Type: SEQUENCE SET; Schema: public; Owner: postgres
--

SELECT pg_catalog.setval('public.history_applicants_id_seq', 23, true);


--
-- TOC entry 3832 (class 0 OID 0)
-- Dependencies: 328
-- Name: notifications_id_seq; Type: SEQUENCE SET; Schema: public; Owner: postgres
--

SELECT pg_catalog.setval('public.notifications_id_seq', 1, false);


--
-- TOC entry 3833 (class 0 OID 0)
-- Dependencies: 315
-- Name: scholarships_id_seq; Type: SEQUENCE SET; Schema: public; Owner: postgres
--

SELECT pg_catalog.setval('public.scholarships_id_seq', 18, true);


--
-- TOC entry 3834 (class 0 OID 0)
-- Dependencies: 330
-- Name: sms_outbox_id_seq; Type: SEQUENCE SET; Schema: public; Owner: postgres
--

SELECT pg_catalog.setval('public.sms_outbox_id_seq', 6, true);


--
-- TOC entry 3613 (class 2606 OID 17795)
-- Name: admins admins_email_key; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.admins
    ADD CONSTRAINT admins_email_key UNIQUE (email);


--
-- TOC entry 3615 (class 2606 OID 17793)
-- Name: admins admins_pkey; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.admins
    ADD CONSTRAINT admins_pkey PRIMARY KEY (admin_id);


--
-- TOC entry 3617 (class 2606 OID 17930)
-- Name: applicants_main applicants_email_key; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.applicants_main
    ADD CONSTRAINT applicants_email_key UNIQUE (email);


--
-- TOC entry 3625 (class 2606 OID 22758)
-- Name: applicants_iskolar applicants_iskolar_pkey; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.applicants_iskolar
    ADD CONSTRAINT applicants_iskolar_pkey PRIMARY KEY (id);


--
-- TOC entry 3619 (class 2606 OID 17926)
-- Name: applicants_main applicants_pkey; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.applicants_main
    ADD CONSTRAINT applicants_pkey PRIMARY KEY (applicant_id);


--
-- TOC entry 3621 (class 2606 OID 18105)
-- Name: applicants_main applicants_student_number_key; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.applicants_main
    ADD CONSTRAINT applicants_student_number_key UNIQUE (student_number);


--
-- TOC entry 3627 (class 2606 OID 40743)
-- Name: history_applicants history_applicants_pkey; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.history_applicants
    ADD CONSTRAINT history_applicants_pkey PRIMARY KEY (id);


--
-- TOC entry 3629 (class 2606 OID 43097)
-- Name: notifications notifications_pkey; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.notifications
    ADD CONSTRAINT notifications_pkey PRIMARY KEY (id);


--
-- TOC entry 3623 (class 2606 OID 20337)
-- Name: scholarships scholarships_pkey; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.scholarships
    ADD CONSTRAINT scholarships_pkey PRIMARY KEY (id);


--
-- TOC entry 3631 (class 2606 OID 43154)
-- Name: sms_outbox sms_outbox_pkey; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.sms_outbox
    ADD CONSTRAINT sms_outbox_pkey PRIMARY KEY (id);


--
-- TOC entry 3632 (class 1259 OID 43155)
-- Name: sms_outbox_status_created_at_idx; Type: INDEX; Schema: public; Owner: postgres
--

CREATE INDEX sms_outbox_status_created_at_idx ON public.sms_outbox USING btree (status, created_at);


--
-- TOC entry 3633 (class 2620 OID 43158)
-- Name: applicants_iskolar trg_app_iskolar_status_ins; Type: TRIGGER; Schema: public; Owner: postgres
--

CREATE TRIGGER trg_app_iskolar_status_ins AFTER INSERT ON public.applicants_iskolar FOR EACH ROW WHEN ((upper(new.status) = ANY (ARRAY['APPROVED'::text, 'REJECTED'::text]))) EXECUTE FUNCTION public.queue_sms_on_status_change();


--
-- TOC entry 3634 (class 2620 OID 43159)
-- Name: applicants_iskolar trg_app_iskolar_status_upd; Type: TRIGGER; Schema: public; Owner: postgres
--

CREATE TRIGGER trg_app_iskolar_status_upd AFTER UPDATE OF status ON public.applicants_iskolar FOR EACH ROW WHEN (((upper(new.status) = ANY (ARRAY['APPROVED'::text, 'REJECTED'::text])) AND (old.status IS DISTINCT FROM new.status))) EXECUTE FUNCTION public.queue_sms_on_status_change();


--
-- TOC entry 3787 (class 3256 OID 35186)
-- Name: applicants_iskolar Allow update of status for anon; Type: POLICY; Schema: public; Owner: postgres
--

CREATE POLICY "Allow update of status for anon" ON public.applicants_iskolar FOR UPDATE USING (true) WITH CHECK (true);


--
-- TOC entry 3788 (class 3256 OID 40795)
-- Name: history_applicants Enable insert for all users; Type: POLICY; Schema: public; Owner: postgres
--

CREATE POLICY "Enable insert for all users" ON public.history_applicants FOR INSERT WITH CHECK (true);


--
-- TOC entry 3786 (class 3256 OID 34082)
-- Name: applicants_iskolar Enable read access for all users; Type: POLICY; Schema: public; Owner: postgres
--

CREATE POLICY "Enable read access for all users" ON public.applicants_iskolar FOR SELECT USING (true);


--
-- TOC entry 3789 (class 3256 OID 40796)
-- Name: history_applicants Enable read access for all users; Type: POLICY; Schema: public; Owner: postgres
--

CREATE POLICY "Enable read access for all users" ON public.history_applicants FOR SELECT USING (true);


--
-- TOC entry 3785 (class 3256 OID 32954)
-- Name: applicants_iskolar allow_insert_applicants; Type: POLICY; Schema: public; Owner: postgres
--

CREATE POLICY allow_insert_applicants ON public.applicants_iskolar FOR INSERT TO authenticated, anon WITH CHECK (true);


--
-- TOC entry 3783 (class 0 OID 22749)
-- Dependencies: 317
-- Name: applicants_iskolar; Type: ROW SECURITY; Schema: public; Owner: postgres
--

ALTER TABLE public.applicants_iskolar ENABLE ROW LEVEL SECURITY;

--
-- TOC entry 3784 (class 0 OID 40734)
-- Dependencies: 321
-- Name: history_applicants; Type: ROW SECURITY; Schema: public; Owner: postgres
--

ALTER TABLE public.history_applicants ENABLE ROW LEVEL SECURITY;

--
-- TOC entry 3812 (class 0 OID 0)
-- Dependencies: 48
-- Name: SCHEMA public; Type: ACL; Schema: -; Owner: pg_database_owner
--

GRANT USAGE ON SCHEMA public TO postgres;
GRANT USAGE ON SCHEMA public TO anon;
GRANT USAGE ON SCHEMA public TO authenticated;
GRANT USAGE ON SCHEMA public TO service_role;


--
-- TOC entry 3813 (class 0 OID 0)
-- Dependencies: 456
-- Name: FUNCTION copy_to_campus_table(); Type: ACL; Schema: public; Owner: postgres
--

GRANT ALL ON FUNCTION public.copy_to_campus_table() TO anon;
GRANT ALL ON FUNCTION public.copy_to_campus_table() TO authenticated;
GRANT ALL ON FUNCTION public.copy_to_campus_table() TO service_role;


--
-- TOC entry 3814 (class 0 OID 0)
-- Dependencies: 457
-- Name: FUNCTION normalize_phone_ph(p text); Type: ACL; Schema: public; Owner: postgres
--

GRANT ALL ON FUNCTION public.normalize_phone_ph(p text) TO anon;
GRANT ALL ON FUNCTION public.normalize_phone_ph(p text) TO authenticated;
GRANT ALL ON FUNCTION public.normalize_phone_ph(p text) TO service_role;


--
-- TOC entry 3815 (class 0 OID 0)
-- Dependencies: 458
-- Name: FUNCTION queue_sms_on_status_change(); Type: ACL; Schema: public; Owner: postgres
--

GRANT ALL ON FUNCTION public.queue_sms_on_status_change() TO anon;
GRANT ALL ON FUNCTION public.queue_sms_on_status_change() TO authenticated;
GRANT ALL ON FUNCTION public.queue_sms_on_status_change() TO service_role;


--
-- TOC entry 3816 (class 0 OID 0)
-- Dependencies: 313
-- Name: TABLE admins; Type: ACL; Schema: public; Owner: postgres
--

GRANT ALL ON TABLE public.admins TO anon;
GRANT ALL ON TABLE public.admins TO authenticated;
GRANT ALL ON TABLE public.admins TO service_role;


--
-- TOC entry 3817 (class 0 OID 0)
-- Dependencies: 317
-- Name: TABLE applicants_iskolar; Type: ACL; Schema: public; Owner: postgres
--

GRANT ALL ON TABLE public.applicants_iskolar TO anon;
GRANT ALL ON TABLE public.applicants_iskolar TO authenticated;
GRANT ALL ON TABLE public.applicants_iskolar TO service_role;


--
-- TOC entry 3818 (class 0 OID 0)
-- Dependencies: 318
-- Name: SEQUENCE applicants_iskolar_id_seq; Type: ACL; Schema: public; Owner: postgres
--

GRANT ALL ON SEQUENCE public.applicants_iskolar_id_seq TO anon;
GRANT ALL ON SEQUENCE public.applicants_iskolar_id_seq TO authenticated;
GRANT ALL ON SEQUENCE public.applicants_iskolar_id_seq TO service_role;


--
-- TOC entry 3819 (class 0 OID 0)
-- Dependencies: 314
-- Name: TABLE applicants_main; Type: ACL; Schema: public; Owner: postgres
--

GRANT ALL ON TABLE public.applicants_main TO anon;
GRANT ALL ON TABLE public.applicants_main TO authenticated;
GRANT ALL ON TABLE public.applicants_main TO service_role;


--
-- TOC entry 3820 (class 0 OID 0)
-- Dependencies: 321
-- Name: TABLE history_applicants; Type: ACL; Schema: public; Owner: postgres
--

GRANT ALL ON TABLE public.history_applicants TO anon;
GRANT ALL ON TABLE public.history_applicants TO authenticated;
GRANT ALL ON TABLE public.history_applicants TO service_role;


--
-- TOC entry 3821 (class 0 OID 0)
-- Dependencies: 322
-- Name: SEQUENCE history_applicants_id_seq; Type: ACL; Schema: public; Owner: postgres
--

GRANT ALL ON SEQUENCE public.history_applicants_id_seq TO anon;
GRANT ALL ON SEQUENCE public.history_applicants_id_seq TO authenticated;
GRANT ALL ON SEQUENCE public.history_applicants_id_seq TO service_role;


--
-- TOC entry 3822 (class 0 OID 0)
-- Dependencies: 329
-- Name: TABLE notifications; Type: ACL; Schema: public; Owner: postgres
--

GRANT ALL ON TABLE public.notifications TO anon;
GRANT ALL ON TABLE public.notifications TO authenticated;
GRANT ALL ON TABLE public.notifications TO service_role;


--
-- TOC entry 3824 (class 0 OID 0)
-- Dependencies: 328
-- Name: SEQUENCE notifications_id_seq; Type: ACL; Schema: public; Owner: postgres
--

GRANT ALL ON SEQUENCE public.notifications_id_seq TO anon;
GRANT ALL ON SEQUENCE public.notifications_id_seq TO authenticated;
GRANT ALL ON SEQUENCE public.notifications_id_seq TO service_role;


--
-- TOC entry 3825 (class 0 OID 0)
-- Dependencies: 316
-- Name: TABLE scholarships; Type: ACL; Schema: public; Owner: postgres
--

GRANT ALL ON TABLE public.scholarships TO anon;
GRANT ALL ON TABLE public.scholarships TO authenticated;
GRANT ALL ON TABLE public.scholarships TO service_role;


--
-- TOC entry 3826 (class 0 OID 0)
-- Dependencies: 315
-- Name: SEQUENCE scholarships_id_seq; Type: ACL; Schema: public; Owner: postgres
--

GRANT ALL ON SEQUENCE public.scholarships_id_seq TO anon;
GRANT ALL ON SEQUENCE public.scholarships_id_seq TO authenticated;
GRANT ALL ON SEQUENCE public.scholarships_id_seq TO service_role;


--
-- TOC entry 3827 (class 0 OID 0)
-- Dependencies: 331
-- Name: TABLE sms_outbox; Type: ACL; Schema: public; Owner: postgres
--

GRANT ALL ON TABLE public.sms_outbox TO anon;
GRANT ALL ON TABLE public.sms_outbox TO authenticated;
GRANT ALL ON TABLE public.sms_outbox TO service_role;


--
-- TOC entry 3829 (class 0 OID 0)
-- Dependencies: 330
-- Name: SEQUENCE sms_outbox_id_seq; Type: ACL; Schema: public; Owner: postgres
--

GRANT ALL ON SEQUENCE public.sms_outbox_id_seq TO anon;
GRANT ALL ON SEQUENCE public.sms_outbox_id_seq TO authenticated;
GRANT ALL ON SEQUENCE public.sms_outbox_id_seq TO service_role;


--
-- TOC entry 2399 (class 826 OID 16490)
-- Name: DEFAULT PRIVILEGES FOR SEQUENCES; Type: DEFAULT ACL; Schema: public; Owner: postgres
--

ALTER DEFAULT PRIVILEGES FOR ROLE postgres IN SCHEMA public GRANT ALL ON SEQUENCES TO postgres;
ALTER DEFAULT PRIVILEGES FOR ROLE postgres IN SCHEMA public GRANT ALL ON SEQUENCES TO anon;
ALTER DEFAULT PRIVILEGES FOR ROLE postgres IN SCHEMA public GRANT ALL ON SEQUENCES TO authenticated;
ALTER DEFAULT PRIVILEGES FOR ROLE postgres IN SCHEMA public GRANT ALL ON SEQUENCES TO service_role;


--
-- TOC entry 2400 (class 826 OID 16491)
-- Name: DEFAULT PRIVILEGES FOR SEQUENCES; Type: DEFAULT ACL; Schema: public; Owner: supabase_admin
--

ALTER DEFAULT PRIVILEGES FOR ROLE supabase_admin IN SCHEMA public GRANT ALL ON SEQUENCES TO postgres;
ALTER DEFAULT PRIVILEGES FOR ROLE supabase_admin IN SCHEMA public GRANT ALL ON SEQUENCES TO anon;
ALTER DEFAULT PRIVILEGES FOR ROLE supabase_admin IN SCHEMA public GRANT ALL ON SEQUENCES TO authenticated;
ALTER DEFAULT PRIVILEGES FOR ROLE supabase_admin IN SCHEMA public GRANT ALL ON SEQUENCES TO service_role;


--
-- TOC entry 2398 (class 826 OID 16489)
-- Name: DEFAULT PRIVILEGES FOR FUNCTIONS; Type: DEFAULT ACL; Schema: public; Owner: postgres
--

ALTER DEFAULT PRIVILEGES FOR ROLE postgres IN SCHEMA public GRANT ALL ON FUNCTIONS TO postgres;
ALTER DEFAULT PRIVILEGES FOR ROLE postgres IN SCHEMA public GRANT ALL ON FUNCTIONS TO anon;
ALTER DEFAULT PRIVILEGES FOR ROLE postgres IN SCHEMA public GRANT ALL ON FUNCTIONS TO authenticated;
ALTER DEFAULT PRIVILEGES FOR ROLE postgres IN SCHEMA public GRANT ALL ON FUNCTIONS TO service_role;


--
-- TOC entry 2402 (class 826 OID 16493)
-- Name: DEFAULT PRIVILEGES FOR FUNCTIONS; Type: DEFAULT ACL; Schema: public; Owner: supabase_admin
--

ALTER DEFAULT PRIVILEGES FOR ROLE supabase_admin IN SCHEMA public GRANT ALL ON FUNCTIONS TO postgres;
ALTER DEFAULT PRIVILEGES FOR ROLE supabase_admin IN SCHEMA public GRANT ALL ON FUNCTIONS TO anon;
ALTER DEFAULT PRIVILEGES FOR ROLE supabase_admin IN SCHEMA public GRANT ALL ON FUNCTIONS TO authenticated;
ALTER DEFAULT PRIVILEGES FOR ROLE supabase_admin IN SCHEMA public GRANT ALL ON FUNCTIONS TO service_role;


--
-- TOC entry 2397 (class 826 OID 16488)
-- Name: DEFAULT PRIVILEGES FOR TABLES; Type: DEFAULT ACL; Schema: public; Owner: postgres
--

ALTER DEFAULT PRIVILEGES FOR ROLE postgres IN SCHEMA public GRANT ALL ON TABLES TO postgres;
ALTER DEFAULT PRIVILEGES FOR ROLE postgres IN SCHEMA public GRANT ALL ON TABLES TO anon;
ALTER DEFAULT PRIVILEGES FOR ROLE postgres IN SCHEMA public GRANT ALL ON TABLES TO authenticated;
ALTER DEFAULT PRIVILEGES FOR ROLE postgres IN SCHEMA public GRANT ALL ON TABLES TO service_role;


--
-- TOC entry 2401 (class 826 OID 16492)
-- Name: DEFAULT PRIVILEGES FOR TABLES; Type: DEFAULT ACL; Schema: public; Owner: supabase_admin
--

ALTER DEFAULT PRIVILEGES FOR ROLE supabase_admin IN SCHEMA public GRANT ALL ON TABLES TO postgres;
ALTER DEFAULT PRIVILEGES FOR ROLE supabase_admin IN SCHEMA public GRANT ALL ON TABLES TO anon;
ALTER DEFAULT PRIVILEGES FOR ROLE supabase_admin IN SCHEMA public GRANT ALL ON TABLES TO authenticated;
ALTER DEFAULT PRIVILEGES FOR ROLE supabase_admin IN SCHEMA public GRANT ALL ON TABLES TO service_role;


-- Completed on 2025-11-05 18:33:05

--
-- PostgreSQL database dump complete
--

\unrestrict tUgg4wODR27grrtYiJjpdrB8dffVuWvdfjEhCF46QFMZFq7xNPFxSQ0JProlhpo

