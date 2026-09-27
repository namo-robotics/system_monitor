# Agent Development Guide

A file for guiding coding agents.

## Overview

This repo implements a system monitor utility with process, disk, service, network, and temperature views. It is written in the [Sun programming language](https://namo-robotics.github.io/sun/).

## Commands

- Never use git commands except readonly ones like `git status` and `git diff`.

## Code Comments

- All code comments should be concise, plain-english written for a general audience of software engineers.
- Every public function, class, module, etc should have a concise, plain-english block comment describing what it does.
- Do not hard-code numeric values that subject to change in comments.

## Commit messages

- Subject: `<scope>: <description>` (scope = subsystem/package/area; imperative; no `feat`/`fix` types).
- Body: blank line, then one concise bullet per key change if not already captured in the subject.
- Do not add AI attribution to commits or PRs (no Co-Authored-By, Generated-with, tool names, or session links).

## Issues and PR Guidelinese

- Never create PRs or issues unless specifically asked by the user.
