# dsr.lex — GDPR Art. 15 (access) export over a roaming subject's OCPI records.
#
# For a roaming EV user identified by their eMSP contract_id (the emaid), this
# gathers every record this party holds about them — CDRs, Sessions and Tokens —
# as one JSON document a controller can hand to the data subject.
#
# EXPORT ONLY, deliberately. As a CPO we are typically the PROCESSOR of a roaming
# user's identity (their eMSP is the controller), and CDRs carry billing / tax
# retention, so erasure is out of scope here and left to the controller's
# instruction; disclosure of a subject's own records (Art. 15) is always available.
#
# Tokens carry contract_id as a column, so they filter at the database. CDRs and
# Sessions carry the subject inside the nested `cdr_token` object, which is not a
# column, so they are fetched and filtered in application code. A deployment
# expecting large volumes should add a generated column / index on
# cdr_token->>'contract_id' and push that filter into SQL.

import "std.list" as list

import "lex-schema/json_value" as jv

import "lex-orm/query" as q

import "lex-orm/predicate" as p

import "lex-orm/connection" as conn

import "lex-orm/error" as dbe

import "./cdrs" as cdrs

import "./sessions" as sessions

import "./tokens" as tokens

# The subject (eMSP contract_id) inside a CDR's or Session's nested cdr_token,
# or "" when absent. This is the only field-extraction that isn't a column query.
fn token_contract_id(rec :: jv.Json) -> Str
  examples {
    token_contract_id(JObj([("cdr_token", JObj([("contract_id", JStr("ES-EMP-C1"))]))])) => "ES-EMP-C1",
    token_contract_id(JObj([])) => ""
  }
{
  match jv.get_field(rec, "cdr_token") {
    None => "",
    Some(tok) => match jv.get_field(tok, "contract_id") {
      None => "",
      Some(cid) => match jv.as_str(cid) {
        None => "",
        Some(s) => s,
      },
    },
  }
}

# Every stored row of a repo, decoded as JSON (Repo[jv.Json] with an identity
# decode, so this returns the raw OCPI documents).
fn fetch_all(repo :: q.Repo[jv.Json], db :: conn.ConnDb) -> [sql] Result[List[jv.Json], dbe.DbErr] {
  q.run_select(q.select(repo), db)
}

fn subject_cdrs(db :: conn.ConnDb, cid :: Str) -> [sql] Result[List[jv.Json], dbe.DbErr] {
  match fetch_all(cdrs.repo(), db) {
    Err(e) => Err(e),
    Ok(rows) => Ok(list.filter(rows, fn (r :: jv.Json) -> Bool {
      token_contract_id(r) == cid
    })),
  }
}

fn subject_sessions(db :: conn.ConnDb, cid :: Str) -> [sql] Result[List[jv.Json], dbe.DbErr] {
  match fetch_all(sessions.repo(), db) {
    Err(e) => Err(e),
    Ok(rows) => Ok(list.filter(rows, fn (r :: jv.Json) -> Bool {
      token_contract_id(r) == cid
    })),
  }
}

# Tokens filter at the DB — contract_id is a top-level column on ocpi_tokens.
fn subject_tokens(db :: conn.ConnDb, cid :: Str) -> [sql] Result[List[jv.Json], dbe.DbErr] {
  q.run_select(q.where_clause(q.select(tokens.repo()), p.eq("contract_id", PStr(cid))), db)
}

# The Art. 15 access document: the subject's CDRs + Sessions + Tokens with counts.
fn export_subject(db :: conn.ConnDb, cid :: Str) -> [sql] Result[jv.Json, dbe.DbErr] {
  match subject_cdrs(db, cid) {
    Err(e) => Err(e),
    Ok(cdr_rows) => match subject_sessions(db, cid) {
      Err(e) => Err(e),
      Ok(sess_rows) => match subject_tokens(db, cid) {
        Err(e) => Err(e),
        Ok(tok_rows) => Ok(JObj([("subject", JStr(cid)), ("cdr_count", JInt(list.len(cdr_rows))), ("session_count", JInt(list.len(sess_rows))), ("token_count", JInt(list.len(tok_rows))), ("cdrs", JList(cdr_rows)), ("sessions", JList(sess_rows)), ("tokens", JList(tok_rows))])),
      },
    },
  }
}

