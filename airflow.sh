#!/bin/bash

set -e

# === CONFIGURABLE ===
AIRFLOW_USER="airflowuser"
AIRFLOW_VERSION="2.9.3"
AIRFLOW_HOME="/home/${AIRFLOW_USER}/airflow"
PYTHON_VERSION="$(python3 --version | cut -d ' ' -f 2 | cut -d '.' -f 1-2)"
CONSTRAINT_URL="https://raw.githubusercontent.com/apache/airflow/constraints-${AIRFLOW_VERSION}/constraints-${PYTHON_VERSION}.txt"

echo "🧑 Creating or validating user '${AIRFLOW_USER}'..."

if ! id -u "${AIRFLOW_USER}" &>/dev/null; then
    sudo useradd -m -s /bin/bash "${AIRFLOW_USER}"
    echo "✅ User '${AIRFLOW_USER}' created"
else
    echo "✅ User '${AIRFLOW_USER}' already exists"
fi

# --- SYSTEM DEPENDENCIES ---
echo "🔧 Installing system dependencies..."
sudo apt update && sudo apt install -y \
    wget gcc python3-dev libpq-dev python3-pip unzip curl \
    build-essential zlib1g-dev libncurses-dev libgdbm-dev libnss3-dev \
    libssl-dev libreadline-dev libffi-dev libsqlite3-dev pkg-config \
    python3-venv

# --- SETUP AIRFLOW DIRECTORIES ---
echo "📂 Setting up Airflow directory at ${AIRFLOW_HOME}..."
sudo mkdir -p "${AIRFLOW_HOME}"
sudo chown -R ${AIRFLOW_USER}:${AIRFLOW_USER} "${AIRFLOW_HOME}"

# --- PYTHON VENV + AIRFLOW INSTALL ---
echo "📦 Creating Airflow virtual environment..."
if [ ! -f "${AIRFLOW_HOME}/venv/bin/activate" ]; then
    sudo -u ${AIRFLOW_USER} python3 -m venv "${AIRFLOW_HOME}/venv"
    sudo -u ${AIRFLOW_USER} bash -c "
        source ${AIRFLOW_HOME}/venv/bin/activate
        pip install --upgrade pip
        pip install 'apache-airflow' --constraint ${CONSTRAINT_URL}
    "
else
    echo "✅ Virtual environment already exists."
fi

# --- INITIALIZE DB + ADMIN USER ---
echo "🔧 Initializing Airflow DB and creating admin user..."
sudo -u ${AIRFLOW_USER} bash -c "
    export AIRFLOW_HOME=${AIRFLOW_HOME}
    source ${AIRFLOW_HOME}/venv/bin/activate
    airflow db init
    airflow users create \
        --username admin \
        --password admin \
        --firstname Admin \
        --lastname User \
        --role Admin \
        --email admin@example.com
"

# --- SYSTEMD SERVICES ---
echo "🛠️ Creating systemd service for Airflow Webserver..."
sudo tee /etc/systemd/system/airflow-webserver.service > /dev/null <<EOF
[Unit]
Description=Airflow Webserver
After=network.target

[Service]
Environment=AIRFLOW_HOME=${AIRFLOW_HOME}
ExecStart=${AIRFLOW_HOME}/venv/bin/airflow webserver --port 8080
Restart=always
User=${AIRFLOW_USER}
WorkingDirectory=${AIRFLOW_HOME}

[Install]
WantedBy=multi-user.target
EOF

echo "🛠️ Creating systemd service for Airflow Scheduler..."
sudo tee /etc/systemd/system/airflow-scheduler.service > /dev/null <<EOF
[Unit]
Description=Airflow Scheduler
After=network.target

[Service]
Environment=AIRFLOW_HOME=${AIRFLOW_HOME}
ExecStart=${AIRFLOW_HOME}/venv/bin/airflow scheduler
Restart=always
User=${AIRFLOW_USER}
WorkingDirectory=${AIRFLOW_HOME}

[Install]
WantedBy=multi-user.target
EOF

echo "🔄 Starting Airflow services..."
sudo systemctl daemon-reexec
sudo systemctl daemon-reload
sudo systemctl enable airflow-webserver airflow-scheduler
sudo systemctl restart airflow-webserver airflow-scheduler
sudo systemctl status airflow-webserver
sudo systemctl status airflow-scheduler

echo "✅ Apache Airflow is up and running!"
echo "🌐 Access the Web UI at http://$(hostname -I | awk '{print $1}'):8080"
